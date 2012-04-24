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

      @aggregate_rels = {}
      aggregate_sources.each do |a|
        focus_model, data_model = case a
          when Array then [a.first, a.second]
          else [a, a]
        end

        agg_rel = Relation.new(@layer_types) # TODO Only go as far as focus
        agg_rel.join_to_model(focus_model)
        agg_rel.join_on_path_thru([focus_model, data_model])
        agg_rel.apply_access_filter_func(@access_filter)

        key_models = @ids_rel.spine_layers_thru(focus_model)
        key_cols = key_models.map{|m| m.arel_primary_key}

        agg_fields = data_model.mochigome_aggregation_settings.
          options[:fields].reject{|a| a[:in_ruby]}
        agg_fields.each_with_index do |a, i|
          d_expr = a[:value_proc].call(data_model.arel_table)
          agg_rel.select_expr(d_expr.as("d%03u" % i))
        end

        @aggregate_rels[focus_model] ||= {}
        @aggregate_rels[focus_model][data_model] = (0..key_cols.length).map{|n|
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

    def create_node_tree(cond)
      root = DataNode.new(:report, @name)
      root.comment = <<-eos
        Mochigome Version: #{Mochigome::VERSION}
        Report Generated: #{Time.now}
        Layers: #{@layer_types.map(&:name).join(" => ")}
        AR Path: #{@ids_rel.full_spine_path.map(&:name).join(" => ")}
      eos
      root.comment.gsub!(/(\n|^) +/, "\\1")

      r = @ids_rel.clone
      r.apply_condition(cond)
      ids_table = @layer_types.first.connection.select_all(r.to_sql)
      fill_layers(ids_table, {[] => root}, @layer_types)

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
      @aggregate_rels.each do |focus_model, data_model_rels|
        # TODO Actually get the key types found in init for this aggregation
        super_types = @layer_types.take_while{|m| m != focus_model}
        data_model_rels.each do |data_model, rel_funcs|
          aggs = data_model.mochigome_aggregation_settings.options[:fields]
          aggs_count = aggs.reject{|a| a[:in_ruby]}.size
          rel_funcs.each do |rel_func|
            q = rel_func.call(cond)
            data_tree = {}
            @layer_types.first.connection.select_all(q.to_sql).each do |row|
              group_values = row.keys.select{|k| k.start_with?("g")}.sort.map{|k| row[k]}
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
            insert_aggregate_data_fields(node, data_tree, data_model)
          end
        end
      end
    end

    def insert_aggregate_data_fields(node, table, data_model)
      if table.is_a? Array
        fields = data_model.mochigome_aggregation_settings.options[:fields]
        # Pre-fill the node with all fields in the right order
        fields.each{|agg| node[agg[:name]] = agg[:default] unless agg[:hidden] }
        agg_row = {} # Hold regular aggs here to be used in ruby-based aggs
        fields.reject{|agg| agg[:in_ruby]}.zip(table).each do |agg, v|
          v ||= agg[:default]
          agg_row[agg[:name]] = v
          node[agg[:name]] = v unless agg[:hidden]
        end
        fields.select{|agg| agg[:in_ruby]}.each do |agg|
          node[agg[:name]] = agg[:ruby_proc].call(agg_row)
        end
        node.children.each do |c|
          insert_aggregate_data_fields(c, [], data_model)
        end
      else
        node.children.each do |c|
          subtable = table[c[:id]] or next
          insert_aggregate_data_fields(c, subtable, data_model)
        end
      end
    end
  end

  private

  class Relation
    def initialize(layers)
      @model_graph = ModelGraph.new
      @spine_layers = layers
      @spine = @model_graph.path_thru(layers) or
        raise QueryError.new("No valid path thru #{layers.inspect}") #TODO Test
      @models = Set.new @spine.map(&:to_real_model)
      @rel = @model_graph.relation_over_path(@spine)

      @spine_layers.each{|m| select_model_id(m)}
    end

    def to_arel
      @rel.clone
    end

    def to_sql
      @rel.to_sql
    end

    def full_spine_path
      @spine.dup
    end

    def spine_layers_thru(model)
      r = @spine.take_while{|m| m != model}
      r << model unless r.size == @spine.size
      r.select{|m| @spine_layers.include? m}
    end

    def clone
      c = super
      c.instance_variable_set :@models, @models.clone
      c.instance_variable_set :@rel, @rel.clone
      c
    end

    def join_to_model(model)
      return if @models.include?(model)

      # Route to it in as few steps as possible, closer to spine end if tie.
      best_path = nil
      (@spine.reverse + (@models.to_a - @spine)).each do |link_model|
        path = @model_graph.path_thru([link_model, model])
        if path && (best_path.nil? || path.size < best_path.size)
          best_path = path
        end
      end

      raise QueryError.new("No path to #{model}") unless best_path
      join_on_path(best_path)
    end

    def join_on_path_thru(path)
      full_path = @model_graph.path_thru(path).uniq
      if full_path
        join_on_path(full_path)
      else
        raise QueryError.new("Cannot route thru #{path.map(&:name).inspect}")
      end
    end

    def join_on_path(path)
      path = path.map(&:to_real_model).uniq
      (0..(path.size-2)).map{|i| [path[i], path[i+1]]}.each do |src, tgt|
        add_join_link src, tgt
      end
    end

    def select_model_id(m)
      @rel = @rel.project(m.arel_primary_key.as("#{m.name}_id"))
    end

    def select_expr(e)
      @model_graph.expr_models(e).each{|m| join_to_model(m)}
      @rel = @rel.project(e)
    end

    def apply_condition(cond)
      return unless cond
      if cond.is_a?(ActiveRecord::Base)
        cond = [cond]
      end
      if cond.is_a?(Array)
        # TODO: Should group by type and use IN expressions
        cond = cond.inject(nil) do |expr, obj|
          subexpr = obj.class.arel_primary_key.eq(obj.id)
          expr ? expr.or(subexpr) : subexpr
        end
      end

      @model_graph.expr_models(cond).each{|m| join_to_model(m)}
      @rel = @rel.where(cond)
    end

    def apply_access_filter_func(func)
      @models.each do |m|
        h = func.call(m)
        h.delete(:join_paths).try :each do |path|
          join_on_path path
        end
        if h[:condition]
          apply_condition h.delete(:condition)
        end
        unless h.empty?
          raise QueryError.new("Unknown assoc filter keys #{h.keys.inspect}")
        end
      end
    end

    private

    def add_join_link(src, tgt)
      raise QueryError.new("Can't join from #{src}, not available") unless
        @models.include?(src)
      return if @models.include?(tgt) # TODO Maybe still apply join conditions?
      @rel = @model_graph.relation_func(src, tgt).call(@rel)
      @models.add tgt
    end
  end
end
