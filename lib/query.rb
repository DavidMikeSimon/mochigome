require 'rgl/adjacency'
require 'rgl/traversal'

module Mochigome
  class Query
    def initialize(layer_types, name = "report")
      # TODO: Validate layer types: not empty, AR, act_as_mochigome_focus, graph correctly, no repeats
      @layer_types = layer_types
      @assoc_path = self.class.path_thru(layer_types)
      @ids_rel = self.class.ids_relation_over_path(@assoc_path)
      @name = name
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

      rel = @ids_rel.where(
        Arel::Table.new(objs.first.class.table_name)[
          objs.first.class.primary_key
        ].in(objs.map(&:id))
      )
      ids_table = @layer_types.first.connection.select_rows(rel.to_sql)
      ids_table = ids_table.map{|row| row.map{|cell| cell.to_i}}

      root = DataNode.new(:report, @name)
      fill_layers(ids_table, {:root => root}, @layer_types)

      root.comment = <<-eos
        Mochigome Version: #{Mochigome::VERSION}
        Time: #{Time.now}
        Layers: #{@layer_types.map(&:name).join(" => ")}
        AR Path: #{@assoc_path.map(&:name).join(" => ")}
      eos
      root.comment.gsub!(/\n +/, "\n")
      root.comment.lstrip!

      return root
    end

    private

    def fill_layers(ids_table, parents, types, parent_col_num = nil)
      return if types.size == 0

      model = types.first
      col_num = @assoc_path.find_index(model)
      cur_ids = Set.new
      cur_to_parent = {}

      ids_table.each do |row|
        cur_id = row[col_num]
        cur_ids.add cur_id
        if parent_col_num
          cur_to_parent[cur_id] ||= Set.new
          cur_to_parent[cur_id].add row[parent_col_num]
        end
      end

      layer = {}
      model.find_each(
        :conditions => {model.primary_key => cur_ids.to_a}
      ) do |obj|
        f = obj.mochigome_focus
        dn = DataNode.new(f.type_name, f.name)
        dn.merge!(f.field_data)
        dn[:internal_type] = obj.class.name

        if parent_col_num
          cur_to_parent.fetch(obj.id).each do |parent_id|
            parents.fetch(parent_id) << dn
          end
        else
          parents[:root] << dn
        end
        layer[obj.id] = dn
      end

      fill_layers(ids_table, layer, types.drop(1), col_num)
    end

    # TODO: Move the stuff below into its own module

    @@assoc_graph = RGL::DirectedAdjacencyGraph.new
    @@graphed_models = Set.new
    @@edge_relation_funcs = {}
    @@shortest_paths = {}

    def self.ids_relation_over_path(path)
      rel = Arel::Table.new(path.first.table_name)
      (0..(path.size-2)).each do |i|
        u = path[i]
        v = path[i+1]
        f = @@edge_relation_funcs[[u,v]]
        raise QueryError.new("No assoc from #{u.name} to #{v.name}") unless f
        rel = f.call(rel)
      end
      rel.project(path.map{|m| Arel::Table.new(m.table_name)[m.primary_key]})
    end

    def self.path_thru(models)
      update_assoc_graph(models.reject{|m| @@assoc_graph.has_vertex?(m)})
      path = [models.first]
      (0..(models.size-2)).each do |i|
        u = models[i]
        v = models[i+1]
        seg = @@shortest_paths[[u,v]]
        raise QueryError.new("Can't travel from #{u.name} to #{v.name}") unless seg
        seg.drop(1).each{|step| path << step}
      end
      unless path.uniq == path
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

        model.reflections.each do |name, assoc|
          next if assoc.through_reflection
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
      end
    end
  end
end
