module Mochigome
  class Query
    def initialize(layer_types, options = {})
      # TODO: Validate layer types: not empty, AR, act_as_mochigome_focus
      @layer_types = layer_types

      @name = options.delete(:root_name).try(:to_s) || "report"
      @access_filter = options.delete(:access_filter) || lambda {|cls| {}}
      # TODO: Validate that aggregate_sources is in the correct format
      aggregate_sources = options.delete(:aggregate_sources) || []
      unless options.empty?
        raise QueryError.new("Unknown options: #{options.keys.inspect}")
      end

      @ids_rel = Relation.new(@layer_types)
      @ids_rel.apply_access_filter_func(@access_filter)

      @aggregate_rels = ActiveSupport::OrderedHash.new
      aggregate_sources.each do |a|
        focus_model, data_model, agg_setting_name = nil, nil, nil
        if a.is_a?(Array) then
          focus_model = a.select{|e| e.is_a?(Class)}.first
          data_model = a.select{|e| e.is_a?(Class)}.last
          agg_setting_name = a.select{|e| e.is_a?(Symbol)}.first || :default
        else
          focus_model = data_model = a
          agg_setting_name = :default
        end

        agg_rel = Relation.new(@layer_types)
        agg_rel.join_on_path_thru([focus_model, data_model])
        agg_rel.apply_access_filter_func(@access_filter)

        key_cols = @ids_rel.spine_layers.map{|m| m.arel_primary_key}

        agg_fields = data_model.
          mochigome_aggregation_settings(agg_setting_name).
          options[:fields].reject{|a| a[:in_ruby]}
        agg_fields.each_with_index do |a, i|
          d_expr = a[:value_proc].call(data_model.arel_table)
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
    end

    def run(cond = nil)
      root = create_node_tree(cond)
      load_aggregate_data(root, cond)
      return root
    end

    private

    def connection
      ActiveRecord::Base.connection
    end

    # TODO: Write a test for situations that use this
    def denilify(v)
      (v.nil? || v.to_s.strip.empty?) ? "(None)" : v
    end

    def create_node_tree(cond)
      root = DataNode.new(:report, @name)
      root.comment = <<-eos
        Mochigome Version: #{Mochigome::VERSION}
        Report Generated: #{Time.now}
        Layers: #{@layer_types.map(&:name).join(" => ")}
      eos
      @ids_rel.joins.each do |src, tgt|
        root.comment += "Join: #{src.name} -> #{tgt.name}\n"
      end
      root.comment.gsub!(/(\n|^) +/, "\\1")

      unless @layer_types.empty?
        r = @ids_rel.clone
        r.apply_condition(cond)
        ids_sql = r.to_sql
        if ids_sql
          ids_table = connection.select_all(ids_sql).map do |row|
            row.each do |k,v|
              row[k] = denilify(v)
            end
          end
          fill_layers(ids_table, {[] => root}, @layer_types)
        end
      end

      root
    end

    def fill_layers(ids_table, parents, types, type_idx = 0)
      return if type_idx >= types.size

      model = types[type_idx]
      layer_ids = Set.new
      cur_to_parent = {}

      parent_types = types.take(type_idx)
      ids_table.each do |row|
        cur_id = row["#{model.name}_id"]
        layer_ids.add cur_id
        cur_to_parent[cur_id] ||= Set.new
        cur_to_parent[cur_id].add parent_types.map{|m| row["#{m.name}_id"]}
      end

      layer = {}
      model.all( # TODO: Find a way to do this with data streaming
        :conditions => {model.primary_key => layer_ids.to_a},
        :order => model.mochigome_focus_settings.get_ordering
      ).each do |obj|
        f = obj.mochigome_focus
        dn = DataNode.new(f.type_name, f.name)
        dn.merge!(f.field_data)

        # TODO: Maybe make special fields below part of ModelExtensions?
        dn[:id] = obj.id
        dn[:internal_type] = model.name

        cur_to_parent.fetch(obj.id).each do |parent_ids_seq|
          cloned = dn.clone
          parents.fetch(parent_ids_seq) << cloned
          layer[parent_ids_seq + [obj.id]] = cloned
        end
      end

      fill_layers(ids_table, layer, types, type_idx + 1)
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
          insert_aggregate_data_fields(node, data_tree, agg_settings)
        end
      end
    end

    def insert_aggregate_data_fields(node, table, agg_settings)
      if table.is_a? Array
        fields = agg_settings.options[:fields]
        # Pre-fill the node with all fields in the right order
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
          insert_aggregate_data_fields(c, [], agg_settings)
        end
      else
        node.children.each do |c|
          subtable = table[c[:id]] || []
          insert_aggregate_data_fields(c, subtable, agg_settings)
        end
      end
    end
  end
end
