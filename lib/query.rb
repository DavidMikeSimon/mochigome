module Mochigome
  class Query
    def initialize(layers, options = {})
      @name = options.delete(:root_name).try(:to_s) || "report"
      access_filter = options.delete(:access_filter) || lambda {|cls| {}}
      aggregate_sources = options.delete(:aggregate_sources) || []
      unless options.empty?
        raise QueryError.new("Unknown options: #{options.keys.inspect}")
      end

      if layers.is_a? Array
        layer_paths = [layers]
      else
        unless layers.is_a?(Hash) &&
        layers.size == 1 &&
        layers.keys.first == :report
          raise QueryError.new("Invalid layer tree")
        end
        layer_paths = Query.tree_root_to_leaf_paths(layers.values.first)
      end
      @lines = layer_paths.map{ |path| QueryLine.new(path, access_filter) }

      aggregate_sources.each do |a|
        @lines.each{|line| line.add_aggregate_source(a)}
      end
    end

    def run(cond = nil)
      model_ids = {}
      parental_seqs = {}
      @lines.each do |line|
        tbl = line.build_id_table(cond)
        parent_models = []
        line.layer_types.each do |model|
          tbl.each do |ids_row|
            i = ids_row["#{model.name}_id"]
            if i
              (model_ids[model] ||= Set.new).add(i)
              parental_seq_key = parent_models.zip(
                parent_models.map{|pm| ids_row["#{pm}_id"]}
              )
              (parental_seqs[parental_seq_key] ||= Set.new).add([model.name, i])
            end
          end
          parent_models << model.name
        end
      end

      model_datanodes = generate_datanodes(model_ids)
      root = create_root_node
      add_datanode_children([], root, model_datanodes, parental_seqs)
      @lines.each do |line|
        line.load_aggregate_data(root, cond)
      end
      return root
    end

    private

    def self.tree_root_to_leaf_paths(t)
      if t.is_a?(Hash)
        t.map{|k, v|
          tree_root_to_leaf_paths(v).map{|p| [k] + p}
        }.flatten(1)
      elsif t.is_a?(Array)
        t.map{|v| tree_root_to_leaf_paths(v)}.flatten(1)
      else
        [[t]]
      end
    end

    def generate_datanodes(model_ids)
      model_datanodes = {}
      model_ids.keys.each do |model|
        # TODO: Find a way to do this without loading all recs at one time
        model.all(
          :conditions => {model.primary_key => model_ids[model].to_a},
          :order => model.mochigome_focus_settings.get_ordering
        ).each_with_index do |rec, seq_idx|
          f = rec.mochigome_focus
          dn = DataNode.new(f.type_name, f.name)
          dn.merge!(f.field_data)
          dn[:id] = rec.id
          dn[:internal_type] = model.name
          (model_datanodes[model.name] ||= {})[rec.id] = [dn, seq_idx]
        end
      end
      return model_datanodes
    end

    def add_datanode_children(path, node, model_datanodes, parental_seqs)
      path_children = parental_seqs[path]
      return unless path_children
      ordered_children = {}
      path_children.each do |model, i|
        src_dn, seq_idx = model_datanodes[model][i]
        dn = src_dn.clone
        full_path = path + [[model, i]]
        dn[:_report_path] = full_path.map(&:first).join("___")
        add_datanode_children(full_path, dn, model_datanodes, parental_seqs)

        # Sorting by left-to-right class order in Query layer tree, then
        # by the order of the records themselves.
        # TODO: This way of getting model_idx could create problems
        # if a class appears more than once in the tree.
        model_idx = @lines.index{|line| line.layer_types.any?{|m| m.name == model}}
        (ordered_children[model_idx] ||= {})[seq_idx] = dn
      end
      ordered_children.keys.sort.each do |k|
        subhash = ordered_children[k]
        subhash.keys.sort.each do |seqkey|
          node.children << subhash[seqkey]
        end
      end
    end

    def create_root_node
      root = DataNode.new(:report, @name)
      root.comment = <<-eos
        Mochigome Version: #{Mochigome::VERSION}
        Report Generated: #{Time.now}
        eos
        # FIXME Show layers and joins for all lines individually
        #Layers: #{@layer_types.map(&:name).join(" => ")}
        #eos
        #@ids_rel.joins.each do |src, tgt|
        #  root.comment += "Join: #{src.name} -> #{tgt.name}\n"
        #end
        root.comment.gsub!(/(\n|^) +/, "\\1")
        return root
    end
  end

  private

  class QueryLine
    attr_accessor :layer_types
    attr_accessor :ids_rel

    def initialize(layer_types, access_filter)
      # TODO: Validate layer types: not empty, AR, act_as_mochigome_focus
      @layer_types = layer_types
      @access_filter = access_filter

      @ids_rel = Relation.new(@layer_types)
      @ids_rel.apply_access_filter_func(@access_filter)

      @aggregate_rels = ActiveSupport::OrderedHash.new
    end

    def add_aggregate_source(a)
      focus_model, data_model, agg_setting_name = nil, nil, nil
      if a.is_a?(Array) then
        focus_model = a.select{|e| e.is_a?(Class)}.first
        data_model = a.select{|e| e.is_a?(Class)}.last
        agg_setting_name = a.select{|e| e.is_a?(Symbol)}.first || :default
      else
        focus_model = data_model = a
        agg_setting_name = :default
      end
      # FIXME Raise exception if a isn't in a correct format

      agg_rel = Relation.new(@layer_types)
      agg_rel.join_on_path_thru([focus_model, data_model])
      agg_rel.apply_access_filter_func(@access_filter)

      key_cols = @ids_rel.spine_layers.map{|m| m.arel_primary_key}

      agg_fields = data_model.
        mochigome_aggregation_settings(agg_setting_name).
        options[:fields].reject{|a| a[:in_ruby]}
      agg_fields.each_with_index do |a, i|
        d_expr = a[:value_proc].call(data_model.arel_table)
        d_expr = d_expr.expr if d_expr.respond_to?(:expr)
        agg_rel.select_expr(d_expr.as("d%03u" % i))
      end

      agg_rel_key = {
        :focus_model => focus_model,
        :data_model => data_model,
        :agg_setting_name => agg_setting_name
      }

      @aggregate_rels[agg_rel_key] = (0..key_cols.length).map{|n|
        lambda {|cond|
          data_rel = agg_rel.clone
          data_rel.apply_condition(cond)
          data_cols = key_cols.take(n) + [data_model.arel_primary_key]
          inner_rel = data_rel.to_arel
          data_cols.each_with_index do |col, i|
            inner_rel.project(col.as("g%03u" % i)).group(col)
          end

          # FIXME: This subtable won't be necessary for all aggregation funcs.
          # When we can avoid it, we should, for performance.
          rel = Arel::SelectManager.new(
            Arel::Table.engine,
            Arel.sql("(#{inner_rel.to_sql}) as mochigome_data")
          )
          d_tbl = Arel::Table.new("mochigome_data")
          agg_fields.each_with_index do |a, i|
            name = "d%03u" % i
            rel.project(a[:agg_proc].call(d_tbl[name]).as(name))
          end
          key_cols.take(n).each_with_index do |col, i|
            name = "g%03u" % i
            rel.project(d_tbl[name].as(name)).group(name)
          end
          rel
        }
      }
    end

    def connection
      ActiveRecord::Base.connection
    end

    # TODO: Write a test for situations that use this
    def denilify(v)
      (v.nil? || v.to_s.strip.empty?) ? "(None)" : v
    end

    def build_id_table(cond)
      if @layer_types.empty?
        return []
      else
        r = @ids_rel.clone
        r.apply_condition(cond)
        ids_sql = r.to_sql
        return connection.select_all(ids_sql).map do |row|
          row.each do |k,v|
            row[k] = denilify(v)
          end
        end
      end
    end

    def load_aggregate_data(node, cond)
      @aggregate_rels.each do |key, rel_funcs|
        data_model = key[:data_model]
        agg_name = key[:agg_setting_name]
        agg_settings = data_model.mochigome_aggregation_settings(agg_name)

        rel_funcs.each do |rel_func|
          q = rel_func.call(cond)
          data_tree = {}
          connection.select_all(q.to_sql).each do |row|
            group_values = row.keys.select{|k| k.start_with?("g")}.sort.map{|k| denilify(row[k])}
            data_values = row.keys.select{|k| k.start_with?("d")}.sort.map{|k| row[k]}
            if group_values.empty?
              data_tree = data_values
            else
              c = data_tree
              group_values.take(group_values.size-1).each do |group_id|
                c = (c[group_id] ||= {})
              end
              c[group_values.last] = data_values
            end
          end
          insert_aggregate_data_fields(node, data_tree, agg_settings, 0)
        end
      end
    end

    def insert_aggregate_data_fields(node, table, agg_settings, depth)
      return unless depth == 0 || node[:internal_type] == @layer_types[depth-1].name
      if table.is_a? Array
        fields = agg_settings.options[:fields]
        # Pre-fill the node with default values in the right order
        fields.each{|fld| node[fld[:name]] = fld[:default] unless fld[:hidden] }
        agg_row = {} # Hold regular results here to be used in ruby-based fields
        fields.reject{|fld| fld[:in_ruby]}.zip(table).each do |fld, v|
          v ||= fld[:default]
          agg_row[fld[:name]] = v
          node[fld[:name]] = v unless fld[:hidden]
        end
        fields.select{|fld| fld[:in_ruby]}.each do |fld|
          node[fld[:name]] = fld[:ruby_proc].call(agg_row)
        end
        node.children.each do |c|
          insert_aggregate_data_fields(c, [], agg_settings, depth+1)
        end
      else
        node.children.each do |c|
          subtable = table[c[:id]] || []
          insert_aggregate_data_fields(c, subtable, agg_settings, depth+1)
        end
      end
    end
  end
end
