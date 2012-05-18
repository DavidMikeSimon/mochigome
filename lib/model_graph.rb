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
      @edge_conditions = {}
      @shortest_paths = {}
    end

    # Take an expression and return a Set of all models it references
    def expr_models(e)
      r = Set.new
      [:expr, :left, :right].each do |m|
        r += expr_models(e.send(m)) if e.respond_to?(m)
      end
      if e.respond_to?(:relation)
        model = @table_to_model[e.relation.name] or
          raise ModelSetupError.new("Table lookup error: #{e.relation.name}")
        r.add model
      end
      r
    end

    def relation_init(model)
      update_assoc_graph([model])
      model.arel_table.project # Project to convert Arel::Table to Arel::Rel
    end

    def edge_condition(u, v)
      @edge_conditions[[u,v]]
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
        model = model_queue.shift.to_real_model
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
          # TODO: Wait, isn't this just a base case of the above?
          @table_to_model[model.table_name] = model
        end

        ignore_assocs = []
        if model.acts_as_mochigome_focus?
          ignore_assocs = model.mochigome_focus_settings.options[:ignore_assocs]
        end

        model.reflections.
        reject{|name, assoc| assoc.through_reflection}.
        reject{|name, assoc| ignore_assocs.include? name}.
        each do |name, assoc|
          # TODO: What about self associations?
          # TODO: What about associations to the same model on different keys?
          # TODO: How to deal with polymorphic? Check for matching has_X assoc?
          next if assoc.options[:polymorphic]
          foreign_model = assoc.klass
          unless @graphed_models.include?(foreign_model)
            model_queue.push(foreign_model)
          end
          edge = [model, foreign_model]
          next if @assoc_graph.has_edge?(*edge) # Ignore duplicate assocs
          @assoc_graph.add_edge(*edge)
          @edge_conditions[edge] = model.assoc_condition(name)
        end

        if model.acts_as_mochigome_focus?
          model.mochigome_focus_settings.options[:custom_assocs].each do |t,e|
            cond = e.call(model.arel_table, t.arel_table)
            [[model, t], [t, model]]. each do |edge|
              @assoc_graph.add_edge(*edge)
              # This deliberately allows custom assocs to overwrite normal ones
              @edge_conditions[edge] = cond
            end
            added_models << t unless added_models.include?(t)
          end
        end
      end

      added_models.each do |model|
        # FIXME: Un-DRY, this is a C&P from above
        ignore_assocs = []
        if model.acts_as_mochigome_focus?
          ignore_assocs = model.mochigome_focus_settings.options[:ignore_assocs]
        end

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
        reject{|name, assoc| ignore_assocs.include? name}.
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
