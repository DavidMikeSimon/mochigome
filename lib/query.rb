require 'rgl/adjacency'
require 'rgl/traversal'

module Mochigome
  class Query
    def initialize(layer_types, options = {})
      # TODO: Validate layer types: not empty, AR, act_as_mochigome_focus
      @layer_types = layer_types
      @layers_path = self.class.path_thru(@layer_types)
      @layers_path or raise QueryError.new("No valid path thru layer list") #TODO Test

      @name = options.delete(:root_name).try(:to_s) || "report"
      @access_filter = options.delete(:access_filter) || lambda {|cls| {}}
      aggregate_sources = options.delete(:aggregate_sources) || []
      unless options.empty?
        raise QueryError.new("Unknown options: #{options.keys.inspect}")
      end

      @ids_rel = self.class.relation_over_path(@layers_path).
        project(@layers_path.map{|m| m.arel_primary_key})
      @ids_rel = access_filtered_relation(@ids_rel, @layers_path)

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
        focus_rel = self.class.relation_over_path(@layers_path)

        @aggregate_rels[focus_model] = {}
        data_models.each do |data_model|
          if focus_model == data_model
            f2d_path = [focus_model]
          else
            #TODO: Handle nil here
            f2d_path = self.class.path_thru([focus_model, data_model])
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
                p = self.class.path_thru([layer, link_model]) + remainder.drop(1) # TODO: Handle path_thru returning nil
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

          agg_data_rel = self.class.relation_over_path(agg_path, focus_rel.dup)
          agg_data_rel = access_filtered_relation(agg_data_rel, @layers_path + agg_path)
          agg_fields = data_model.mochigome_aggregation_settings.options[:fields].reject{|a| a[:in_ruby]}
          agg_fields.each_with_index do |a, i|
            agg_data_rel.project(a[:value_proc].call(data_model.arel_table).as("d#{i}"))
          end

          @aggregate_rels[focus_model][data_model] = (0..key_cols.length).map{|n|
            lambda {|cond|
              d_rel = agg_data_rel.dup
              d_cols = key_cols.take(n) + [data_model.arel_primary_key]
              d_cols.each_with_index do |col, i|
                d_rel.project(col.as("g#{i}")).group(col)
              end
              d_rel.where(cond) if cond

              # FIXME: This subtable won't be necessary for all forms of aggregation.
              # When we can avoid it, we should, because query performance is greatly increased.
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
        self.class.expr_tables(cond).each do |t|
          raise QueryError.new("Condition table #{t} not in layer list") unless
            @layers_path.any?{|m| m.real_model? && m.table_name == t}
        end
      end

      q = @ids_rel.dup
      q.where(cond) if cond
      ids_table = @layer_types.first.connection.select_rows(q.to_sql)
      ids_table = ids_table.map do |row|
        # FIXME: Should do this conversion based on type of column
        row.map{|cell| cell =~ /^\d+$/ ? cell.to_i : cell}
      end

      fill_layers(ids_table, {[] => root}, @layer_types)

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
            r = self.class.relation_func(path[i], path[i+1]).call(r)
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

    def fill_layers(ids_table, parents, types, parent_col_nums = [])
      return if types.size == 0

      model = types.first
      col_num = @layers_path.find_index(model)
      layer_ids = Set.new
      cur_to_parent = {}

      ids_table.each do |row|
        cur_id = row[col_num]
        layer_ids.add cur_id
        cur_to_parent[cur_id] ||= Set.new
        cur_to_parent[cur_id].add parent_col_nums.map{|i| row[i]}
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

      fill_layers(ids_table, layer, types.drop(1), parent_col_nums + [col_num])
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

    # TODO: Move the stuff below into its own module

    def self.expr_tables(e)
      # TODO: This is kind of hacky, Arel probably has a better way
      # to do this with its API.
      r = Set.new
      [:expr, :left, :right].each do |m|
        r += expr_tables(e.send(m)) if e.respond_to?(m)
      end
      r.add e.relation.name if e.respond_to?(:relation)
      r
    end

    @@graphed_models = Set.new
    @@assoc_graph = RGL::DirectedAdjacencyGraph.new
    @@edge_relation_funcs = {}
    @@shortest_paths = {}

    def self.relation_over_path(path, rel = nil)
      real_path = path.map{|e| (e.real_model? ? e : e.model)}.uniq
      # Project ensures that we return a Rel, not a Table, even if path is empty
      rel ||= real_path.first.arel_table.project
      (0..(real_path.size-2)).each do |i|
        rel = relation_func(real_path[i], real_path[i+1]).call(rel)
      end
      rel
    end

    def self.relation_func(u, v)
      @@edge_relation_funcs[[u,v]] or
        raise QueryError.new "No assoc from #{u.name} to #{v.name}"
    end

    def self.path_thru(models)
      update_assoc_graph(models)
      model_queue = models.dup
      path = [model_queue.shift]
      until model_queue.empty?
        src = path.last
        tgt = model_queue.shift
        real_src = src.real_model? ? src : src.model
        real_tgt = tgt.real_model? ? tgt : tgt.model
        unless real_src == real_tgt
          seg = @@shortest_paths[[real_src,real_tgt]]
          unless seg
            raise QueryError.new("No path: #{real_src.name} to #{real_tgt.name}")
          end
          path.concat seg.take(seg.size-1).drop(1)
        end
        path << tgt
      end
      unless path.uniq.size == path.size
        raise QueryError.new(
          "Path thru #{models.map(&:name).join('-')} doubles back: " +
          path.map(&:name).join('-')
        )
      end
      path
    end

    def self.update_assoc_graph(models)
      model_queue = models.dup
      added_models = []
      until model_queue.empty?
        model = model_queue.shift
        next if model.is_a?(SubgroupModel)
        next if @@graphed_models.include? model
        @@graphed_models.add model
        added_models << model

        model.reflections.
        reject{|name, assoc| assoc.through_reflection}.
        each do |name, assoc|
          # TODO: What about self associations?
          # TODO: What about associations to the same model on different keys?
          next if assoc.options[:polymorphic] # TODO How to deal with these? Check for matching has_X assoc?
          foreign_model = assoc.klass
          edge = [model, foreign_model]
          next if @@assoc_graph.has_edge?(*edge) # Ignore duplicate assocs
          @@assoc_graph.add_edge(*edge)
          @@edge_relation_funcs[edge] = model.arelified_assoc(name)
          unless @@graphed_models.include?(foreign_model)
            model_queue.push(foreign_model)
          end
        end
      end

      added_models.each do |model|
        next unless @@assoc_graph.has_vertex?(model)
        path_tree = @@assoc_graph.bfs_search_tree_from(model).reverse
        path_tree.depth_first_search do |tgt_model|
          next if tgt_model == model
          path = [tgt_model]
          while (parent = path_tree.adjacent_vertices(path.first).first)
            path.unshift parent
          end
          @@shortest_paths[[model,tgt_model]] = path
        end

        # Use through reflections as a hint for preferred indirect paths
        model.reflections.
        select{|name, assoc| assoc.through_reflection}.
        each do |name, assoc|
          begin
            foreign_model = assoc.klass
            join_model = assoc.through_reflection.klass
          rescue NameError
            # FIXME Can't handle polymorphic through reflection
          end
          edge = [model,foreign_model]
          next if @@shortest_paths[edge].try(:size).try(:<, 3)
          @@shortest_paths[edge] = [model, join_model, foreign_model]
        end
      end
    end
  end
end
