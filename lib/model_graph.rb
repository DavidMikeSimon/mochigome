require 'rgl/adjacency'
require 'rgl/traversal'

module Mochigome
  module ModelGraph
    private

    # Take an expression and return a Set of all tables it references
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
