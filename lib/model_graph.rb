# TODO: Write some unit tests for this module

require 'rgl/adjacency'
require 'rgl/traversal'

module Mochigome
  private

  class ModelGraph
    def initialize
      @graphed_models = Set.new
      @table_to_model = {}
      @assoc_graph = RGL::DirectedAdjacencyGraph.new
      @edge_relation_funcs = {}
      @shortest_paths = {}
    end

    # Take an expression and return a Set of all models it references
    def expr_models(e)
      r = Set.new
      [:expr, :left, :right].each do |m|
        r += expr_models(e.send(m)) if e.respond_to?(m)
      end
      if e.respond_to?(:relation)
        model = @table_to_model[e.relation.name]
        raise ModelSetupError.new("Table->model lookup error") unless model
        r.add model
      end
      r
    end

    def relation_over_path(path)
      real_path = path.map(&:to_real_model).uniq
      # Project ensures that we return a Rel, not a Table, even if path is empty
      rel = real_path.first.arel_table.project
      (0..(real_path.size-2)).each do |i|
        rel = relation_func(real_path[i], real_path[i+1]).call(rel)
      end
      rel
    end

    def relation_func(u, v)
      @edge_relation_funcs[[u,v]] or
        raise QueryError.new "No assoc from #{u.name} to #{v.name}"
    end

    def path_thru(models)
      update_assoc_graph(models)
      model_queue = models.dup
      path = [model_queue.shift]
      until model_queue.empty?
        src = path.last
        tgt = model_queue.shift
        next if src == tgt
        real_src = src.to_real_model
        real_tgt = tgt.to_real_model
        unless real_src == real_tgt
          seg = @shortest_paths[[real_src,real_tgt]]
          return nil unless seg
          path.concat seg.take(seg.size-1).drop(1)
        end
        path << tgt
      end

      # Don't return any paths that double back
      return nil unless path.uniq.size == path.size
      path
    end

    private

    def update_assoc_graph(models)
      model_queue = models.dup
      added_models = []
      until model_queue.empty?
        model = model_queue.shift
        next if model.is_a?(SubgroupModel)
        next if @graphed_models.include? model
        @graphed_models.add model
        added_models << model

        if @table_to_model.has_key?(model.table_name)
          # TODO Test this!
          # Find the nearest common ancestor that derives from AR::Base
          common = nil
          [model, @table_to_model[model.table_name]].each do |tgt|
            a = tgt.ancestors
            a = a.select{|c| c.ancestors.include?(ActiveRecord::Base)}
            if common.nil?
              common = a
            else
              common = common & a
            end
          end

          if common.empty? || common.first == ActiveRecord::Base
            raise ModelSetupError.new(
              "Unrelated models %s and %s both claim to use table %s" %
              [model, @table_to_model[model.table_name], model.table_name]
            )
          end
          @table_to_model[model.table_name] = common.first
        else
          @table_to_model[model.table_name] = model
        end

        model.reflections.
        reject{|name, assoc| assoc.through_reflection}.
        each do |name, assoc|
          # TODO: What about self associations?
          # TODO: What about associations to the same model on different keys?
          next if assoc.options[:polymorphic] # TODO How to deal with these? Check for matching has_X assoc?
          foreign_model = assoc.klass
          edge = [model, foreign_model]
          next if @assoc_graph.has_edge?(*edge) # Ignore duplicate assocs
          @assoc_graph.add_edge(*edge)
          @edge_relation_funcs[edge] = model.arelified_assoc(name)
          unless @graphed_models.include?(foreign_model)
            model_queue.push(foreign_model)
          end
        end
      end

      added_models.each do |model|
        next unless @assoc_graph.has_vertex?(model)
        path_tree = @assoc_graph.bfs_search_tree_from(model).reverse
        path_tree.depth_first_search do |tgt_model|
          next if tgt_model == model
          path = [tgt_model]
          while (parent = path_tree.adjacent_vertices(path.first).first)
            path.unshift parent
          end
          @shortest_paths[[model,tgt_model]] = path
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
          next if @shortest_paths[edge].try(:size).try(:<, 3)
          @shortest_paths[edge] = [model, join_model, foreign_model]
        end
      end
    end
  end
end
