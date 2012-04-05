module Mochigome
  class Query
    def initialize(layer_types, options = {})
      # TODO: Validate layer types: not empty, AR, act_as_mochigome_focus
      @layer_types = layer_types
      @layers_path = ModelGraph.path_thru(@layer_types)

      @name = options.delete(:root_name).try(:to_s) || "report"
      @access_filter = options.delete(:access_filter) || lambda {|cls| {}}
      aggregate_sources = options.delete(:aggregate_sources) || []
      unless options.empty?
        raise QueryError.new("Unknown options: #{options.keys.inspect}")
      end

      @ids_rel = Relation.new(@layer_types)
      @ids_rel.apply_access_filter_func(@access_filter)

      # TODO: Validate that aggregate_sources is in the correct format
      aggs_by_model = {}
      aggregate_sources.each do |a|
        if a.instance_of?(Array)
          focus_cls, data_cls = a.first, a.second
        else
          focus_cls, data_cls = a, a
        end
        aggs_by_model[focus_cls] ||= []
        aggs_by_model[focus_cls] << data_cls
      end

      @aggregate_rels = {}
      aggs_by_model.each do |focus_model, data_models|
        @aggregate_rels[focus_model] = {}
        data_models.each do |data_model|
          agg_rel = Relation.new(@layer_types) # TODO Only go to focus
          agg_rel.join_to_model(focus_model)

          f2d_path = ModelGraph.path_thru([focus_model, data_model]).uniq
          agg_rel.join_on_path(f2d_path)
          agg_rel.apply_access_filter_func(@access_filter)

          focus_idx = @layers_path.index(focus_model)
          key_path = focus_idx ? @layers_path.take(focus_idx+1) : @layers_path
          key_path = key_path.select{|m| @layer_types.include?(m)}
          key_cols = key_path.map{|m| m.arel_primary_key}

          agg_fields = data_model.mochigome_aggregation_settings.
            options[:fields].reject{|a| a[:in_ruby]}
          agg_fields.each_with_index do |a, i|
            d_expr = a[:value_proc].call(data_model.arel_table)
            agg_rel.select_expr(d_expr.as("d%03u" % i))
          end

          @aggregate_rels[focus_model][data_model] = (0..key_cols.length).map{|n|
            lambda {|cond|
              d_rel = agg_rel.to_arel
              d_cols = key_cols.take(n) + [data_model.arel_primary_key]
              d_cols.each_with_index do |col, i|
                d_rel.project(col.as("g%03u" % i)).group(col)
              end
              d_rel.where(cond) if cond

              # FIXME: This subtable won't be necessary for all aggregation funcs.
              # When we can avoid it, we should, for performance.
              a_rel = Arel::SelectManager.new(
                Arel::Table.engine,
                Arel.sql("(#{d_rel.to_sql}) as mochigome_data")
              )
              d_tbl = Arel::Table.new("mochigome_data")
              agg_fields.each_with_index do |a, i|
                name = "d%03u" % i
                outer_name = "o" + name
                a_rel.project(a[:agg_proc].call(d_tbl[name]).as(outer_name))
              end
              key_cols.take(n).each_with_index do |col, i|
                name = "g%03u" % i
                outer_name = "o" + name
                a_rel.project(d_tbl[name].as(outer_name)).group(outer_name)
              end
              a_rel
            }
          }
        end
      end
    end

    def run(cond = nil)
      root = DataNode.new(:report, @name)

      if cond.is_a?(ActiveRecord::Base)
        cond = [cond]
      end
      if cond.is_a?(Array)
        return root if cond.empty?
        cond = cond.inject(nil) do |expr, obj|
          subexpr = obj.class.arel_primary_key.eq(obj.id)
          expr ? expr.or(subexpr) : subexpr
        end
      end

      r = @ids_rel.dup
      r.apply_condition(cond) if cond
      ids_table = @layer_types.first.connection.select_all(r.to_sql)

      fill_layers(ids_table, {[] => root}, @layer_types)

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
              group_values = row.keys.select{|k| k.start_with?("og")}.sort.map{|k| row[k]}
              data_values = row.keys.select{|k| k.start_with?("od")}.sort.map{|k| row[k]}
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
            insert_aggregate_data_fields(root, data_tree, data_model)
          end
        end
      end

      root.comment = <<-eos
        Mochigome Version: #{Mochigome::VERSION}
        Report Generated: #{Time.now}
        Layers: #{@layer_types.map(&:name).join(" => ")}
        AR Path: #{@layers_path.map(&:name).join(" => ")}
      eos
      root.comment.gsub!(/\n +/, "\n")
      root.comment.lstrip!

      return root
    end

    private

    def access_filtered_relation(r, models)
      joined = Set.new
      models.uniq.each do |model|
        h = @access_filter.call(model)
        h.delete(:join_paths).try :each do |path|
          (0..(path.size-2)).each do |i|
            next if models.include?(path[i+1]) or joined.include?(path[i+1])
            r = ModelGraph.relation_func(path[i], path[i+1]).call(r)
            joined.add path[i+1]
          end
        end
        if h[:condition]
          r = r.where(h.delete(:condition))
        end
        unless h.empty?
          raise QueryError.new("Unknown assoc filter keys #{h.keys.inspect}")
        end
      end
      r
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
          duped = dn.dup
          parents.fetch(parent_ids_seq) << duped
          layer[parent_ids_seq + [obj.id]] = duped
        end
      end

      fill_layers(ids_table, layer, types, type_idx + 1)
    end

    def insert_aggregate_data_fields(node, table, data_model)
      if table.is_a? Array
        fields = data_model.mochigome_aggregation_settings.options[:fields]
        # Pre-fill the node with all fields in the right order
        fields.each{|agg| node[agg[:name]] = nil unless agg[:hidden] }
        agg_row = {} # Hold regular aggs here to be used in ruby-based aggs
        fields.reject{|agg| agg[:in_ruby]}.zip(table).each do |agg, v|
          agg_row[agg[:name]] = v
          node[agg[:name]] = v unless agg[:hidden]
        end
        fields.select{|agg| agg[:in_ruby]}.each do |agg|
          node[agg[:name]] = agg[:ruby_proc].call(agg_row)
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
      @spine_layers = layers
      @spine = ModelGraph.path_thru(layers) or
        raise QueryError.new("No valid path thru #{layers.inspect}") #TODO Test
      @models = Set.new @spine
      @rel = ModelGraph.relation_over_path(@spine)

      @spine_layers.each{|m| select_model_id(m)}
    end

    def to_arel
      @rel.clone
    end

    def to_sql
      @rel.to_sql
    end

    def clone
      c = super
      c.instance_variable_set :@spine, @spine.dup
      c.instance_variable_set :@models, @models.dup
      c.instance_variable_set :@rel, @rel.project
      c
    end

    def join_to_model(model)
      return if @models.include?(model)

      # Route to it in as few steps as possible, closer to spine end if tie.
      best_path = nil
      (@spine.reverse + (@models.to_a - @spine)).each do |link_model|
        path = ModelGraph.path_thru([link_model, model])
        if path && (best_path.nil? || path.size < best_path.size)
          best_path = path
        end
      end

      raise QueryError.new("No path to #{model}") unless best_path
      join_on_path(best_path)
    end

    def join_on_path(path)
      path = path.map{|e| (e.real_model? ? e : e.model)}.uniq
      (0..(path.size-2)).map{|i| [path[i], path[i+1]]}.each do |src, tgt|
        add_join_link src, tgt
      end
    end

    def select_model_id(m)
      @rel = @rel.project(m.arel_primary_key.as("#{m.name}_id"))
    end

    def select_expr(e)
      ModelGraph.expr_models(e).each{|m| join_to_model(m)}
      @rel = @rel.project(e)
    end

    def apply_condition(cond)
      ModelGraph.expr_models(cond).each{|m| join_to_model(m)}
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
      @rel = ModelGraph.relation_func(src, tgt).call(@rel)
      @models.add tgt
    end
  end
end
