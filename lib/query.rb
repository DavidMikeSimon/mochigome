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
        # Need to do a relation over the entire path in case query has
        # a condition on something other than the focus model layer.
        # TODO: Would be better to only do this if necesssitated by the
        # conditions supplied to the query when it is ran, and/or
        # the access filter.
        focus_rel = ModelGraph.relation_over_path(@layers_path)

        @aggregate_rels[focus_model] = {}
        data_models.each do |data_model|
          if focus_model == data_model
            f2d_path = [focus_model]
          else
            #TODO: Handle nil here
            f2d_path = ModelGraph.path_thru([focus_model, data_model])
          end
          agg_path = nil
          key_path = nil
          f2d_path.each do |link_model|
            remainder = f2d_path.drop_while{|m| m != link_model}
            next if (remainder.drop(1) & @layers_path).size > 0
            if @layers_path.include?(link_model)
              agg_path = remainder
              key_path = @layers_path.take(@layers_path.index(focus_model)+1)
              break
            else
              # Route it from the closest layer model
              @layers_path.reverse.each do |layer|
                p = ModelGraph.path_thru([layer, link_model]) + remainder.drop(1) # TODO: Handle path_thru returning nil
                next if (p.drop(1) & @layers_path).size > 0
                next if p.uniq.size != p.size
                if agg_path.nil? || p.size < agg_path.size
                  agg_path = p
                  key_path = @layers_path
                end
              end
            end
          end

          key_cols = key_path.map{|m| m.arel_primary_key }

          agg_data_rel = ModelGraph.relation_over_path(agg_path, focus_rel.dup)
          agg_data_rel = access_filtered_relation(agg_data_rel, @layers_path + agg_path)
          agg_fields = data_model.mochigome_aggregation_settings.options[:fields].reject{|a| a[:in_ruby]}
          agg_joined_models = @layers_path + agg_path
          agg_fields.each_with_index do |a, i|
            (a[:joins] || []).each do |m|
              unless agg_joined_models.include?(m)
                cand = nil
                agg_joined_models.each do |agg_join_src_m|
                  p = ModelGraph.path_thru([agg_join_src_m, m])
                  if p && (cand.nil? || p.size < cand.size)
                    cand = p
                  end
                end
                if cand
                  agg_data_rel = ModelGraph.relation_over_path(cand, agg_data_rel)
                  agg_joined_models += cand
                else
                  raise QueryError.new("Can't join from query to agg join model #{m.name}") # TODO: Test this
                end
              end
            end
            d_expr = a[:value_proc].call(data_model.arel_table)
            agg_data_rel.project(d_expr.as("d#{i}"))
          end

          @aggregate_rels[focus_model][data_model] = (0..key_cols.length).map{|n|
            lambda {|cond|
              d_rel = agg_data_rel.dup
              d_cols = key_cols.take(n) + [data_model.arel_primary_key]
              d_cols.each_with_index do |col, i|
                d_rel.project(col.as("g#{i}")).group(col)
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
                a_rel.project(a[:agg_proc].call(d_tbl["d#{i}"]))
              end
              key_cols.take(n).each_with_index do |col, i|
                outer_name = "og#{i}"
                a_rel.project(d_tbl["g#{i}"].as(outer_name)).group(outer_name)
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
      if cond
        ModelGraph.expr_tables(cond).each do |t|
          raise QueryError.new("Condition table #{t} not in layer list") unless
            @layers_path.any?{|m| m.real_model? && m.table_name == t}
        end
      end

      r = @ids_rel.dup
      r.apply_condition(cond) if cond
      ids_table = @layer_types.first.connection.select_all(r.to_sql)

      fill_layers(ids_table, {[] => root}, @layer_types.dup)

      @aggregate_rels.each do |focus_model, data_model_rels|
        super_types = @layer_types.take_while{|m| m != focus_model}
        super_cols = super_types.map{|m| @layers_path.find_index(m)}
        data_model_rels.each do |data_model, rel_funcs|
          aggs = data_model.mochigome_aggregation_settings.options[:fields]
          aggs_count = aggs.reject{|a| a[:in_ruby]}.size
          rel_funcs.each do |rel_func|
            q = rel_func.call(cond)
            data_tree = {}
            # Each row has aggs_count data fields, followed by the id fields
            # from least specific to most.
            @layer_types.first.connection.select_rows(q.to_sql).each do |row|
              if row.size == aggs_count
                data_tree = row.take(aggs_count)
              else
                c = data_tree
                super_cols.each_with_index do |sc_num, sc_idx|
                  break if aggs_count+sc_idx >= row.size-1
                  col_num = aggs_count + sc_num
                  c = (c[row[col_num]] ||= {})
                end
                c[row.last] = row.take(aggs_count)
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

    def fill_layers(ids_table, parents, types, parent_types = [])
      return if types.size == 0

      model = types.shift
      layer_ids = Set.new
      cur_to_parent = {}

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

      fill_layers(ids_table, layer, types, parent_types + [model])
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
      @rel.project # FIXME Should I trust and use Arel's dup function instead?
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

    def apply_condition(cond)
      # TODO: Join if necessary
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
