require 'rgl/adjacency'
require 'rgl/traversal'

module Mochigome
  class Query
    def initialize(layer_types, aggregate_data_sources = [], name = "report")
      # TODO: Validate layer types: not empty, AR, act_as_mochigome_focus, graph correctly, no repeats
      @layer_types = layer_types
      @layers_path = self.class.path_thru(layer_types)
      @name = name

      @ids_rel = self.class.relation_over_path(@layers_path).
        project(@layers_path.map{|m|
          Arel::Table.new(m.table_name)[m.primary_key]
        })

      # TODO: Validate that aggregate_data_sources is in the correct format
      aggs_by_model = {}
      aggregate_data_sources.each do |focus_cls, data_cls|
        aggs_by_model[focus_cls] ||= []
        aggs_by_model[focus_cls] << data_cls
      end

      @aggregate_rels = {}
      aggs_by_model.each do |focus_model, data_models|
        # TODO: Properly handle focus model that is not in layer types list
        key_path = @layers_path.take_while{|m| m != focus_model} + [focus_model]
        key_cols = key_path.map{|m|
          Arel::Table.new(m.table_name)[m.primary_key]
        }

        # Need to do a relation over the entire path in case query runs
        # on something other than the focus model layer.
        # TODO: Would be better to only do this if necessesitated by the
        # conditions supplied to the query when it is ran.
        focus_rel = self.class.relation_over_path(@layers_path).group(key_cols)
        @aggregate_rels[focus_model] = {}
        data_models.each do |data_model|
          f2d_path = self.class.path_thru([focus_model, data_model]) #TODO: Handle nil here
          agg_path = nil
          f2d_path.reverse.each do |link_model|
            # TODO: Properly handle focus model that is not in layer types list
            if @layers_path.include?(link_model)
              agg_path = f2d_path.drop_while{|m| m != link_model}
              break
            end
          end

          agg_rel = self.class.relation_over_path(agg_path, focus_rel.dup)
          data_tbl = Arel::Table.new(data_model.table_name)
          agg_rel.project(key_cols + data_model.mochigome_aggregations.map{|a|
            a[:proc].call(data_tbl)
          })
          @aggregate_rels[focus_model][data_model] = agg_rel
        end
      end
    end

    def run(objs)
      objs = [objs] unless objs.is_a?(Enumerable)

      # Empty DataNode for empty input
      return DataNode.new(:report, @name) if objs.size == 0

      # TODO: Theoretically we could limit on multiple types at once, right?
      unless objs.all?{|obj| obj.class == objs.first.class}
        raise QueryError.new("Query target objects must all be the same type")
      end

      unless @layer_types.any?{|layer| objs.first.is_a?(layer)}
        raise QueryError.new("Query target's class must be in layer list")
      end

      objs_condition_f = lambda{|r| r.dup.where(
        Arel::Table.new(objs.first.class.table_name)[
          objs.first.class.primary_key
        ].in(objs.map(&:id))
      )}

      q = objs_condition_f.call(@ids_rel)
      ids_table = @layer_types.first.connection.select_rows(q.to_sql)
      ids_table = ids_table.map{|row| row.map{|cell| cell.to_i}}

      root = DataNode.new(:report, @name)
      fill_layers(ids_table, {:root => root}, @layer_types)

      @aggregate_rels.each do |focus_model, data_model_rels|
        super_types = @layer_types.take_while{|m| m != focus_model}
        super_cols = super_types.map{|m| @layers_path.find_index(m)}
        focus_col = @layers_path.find_index(focus_model)
        data_model_rels.each do |data_model, rel|
          agg_fields = data_model.mochigome_aggregations.size
          q = objs_condition_f.call(rel)
          data_tree = {}
          @layer_types.first.connection.select_rows(q.to_sql).each do |row|
            c = data_tree
            super_cols.each do |i|
              c = (c[row[i].to_i] ||= {})
            end
            c[row[focus_col].to_i] = row.drop(row.size - agg_fields)
          end
          insert_aggregate_data_fields(root, data_tree, data_model)
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

    def fill_layers(ids_table, parents, types, parent_col_num = nil)
      return if types.size == 0

      model = types.first
      col_num = @layers_path.find_index(model)
      layer_ids = Set.new
      cur_to_parent = {}

      ids_table.each do |row|
        cur_id = row[col_num]
        layer_ids.add cur_id
        if parent_col_num
          cur_to_parent[cur_id] ||= Set.new
          cur_to_parent[cur_id].add row[parent_col_num]
        end
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
        dn[:internal_type] = obj.class.name

        if parent_col_num
          duping = false
          cur_to_parent.fetch(obj.id).each do |parent_id|
            parents.fetch(parent_id) << (duping ? dn.dup : dn)
            duping = true
          end
        else
          parents[:root] << dn
        end
        layer[obj.id] = dn
      end

      fill_layers(ids_table, layer, types.drop(1), col_num)
    end

    def insert_aggregate_data_fields(node, table, data_model)
      if table.is_a? Array
        data_model.mochigome_aggregations.zip(table).each do |agg, v|
          node[agg[:name]] = v
        end
      else
        node.children.each do |c|
          subtable = table[c[:id]] or next
          insert_aggregate_data_fields(c, subtable, data_model)
        end
      end
    end

    # TODO: Move the stuff below into its own module

    @@graphed_models = Set.new
    @@assoc_graph = RGL::DirectedAdjacencyGraph.new
    @@edge_relation_funcs = {}
    @@shortest_paths = {}

    def self.relation_over_path(path, rel = nil)
      rel ||= Arel::Table.new(path.first.table_name)
      (0..(path.size-2)).each do |i|
        rel = relation_func(path[i], path[i+1]).call(rel)
      end
      rel
    end

    def self.relation_func(u, v)
      @@edge_relation_funcs[[u,v]] or
        raise QueryError.new "No assoc from #{u.name} to #{v.name}"
    end

    def self.path_thru(models)
      update_assoc_graph(models)
      path = [models.first]
      (0..(models.size-2)).each do |i|
        u = models[i]
        v = models[i+1]
        next if u == v
        seg = @@shortest_paths[[u,v]]
        raise QueryError.new("Can't travel from #{u.name} to #{v.name}") unless seg
        seg.drop(1).each{|step| path << step}
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
