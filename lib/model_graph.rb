# TODO: Write some unit tests for this module

require 'rgl/adjacency'
require 'rgl/traversal'

module Mochigome
  private

  class ModelGraph
    def initialize
      @graphed_models = Set.new
      @table_to_model = {}
      @assoc_graph = RGL::DirectedAdjacencyGraph.new(OrderedSet)
      # TODO Also maybe need to do this with hashes used internally in traversal
      @assoc_graph.instance_variable_set( # Make path choice more predictable
        :@vertice_dict,
        ActiveSupport::OrderedHash.new
      )
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
        model = nil
        begin
          model = @table_to_model[e.relation.name] or
            raise ModelSetupError.new("Table lookup error: #{e.relation.name}")
        rescue ModelSetupError
          Dir.glob(RAILS_ROOT + '/app/models/*.rb').each do |path|
            clsname = File.basename(path).sub(/\.rb$/, "").classify
            require File.expand_path(path) unless Object.const_defined?(clsname)
          end
          Object.subclasses_of(ActiveRecord::Base).each do |m|
            if m.table_name == e.relation.name
              model = m
              break
            end
          end
          raise unless model
        end
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
          opts = model.mochigome_focus_settings.options
          ignore_assocs = opts[:ignore_assocs]
        end

        model.reflections.
        reject{|name, assoc| assoc.through_reflection}.
        reject{|name, assoc| ignore_assocs.include? name.to_sym}.
        to_a.sort{|a,b| a.first.to_s <=> b.first.to_s}.
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
            next if ignore_assocs.include?(t.to_s.to_sym)
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
      end

      added_models.each do |model|
        ignore_assocs, model_preferred_paths = [], {}
        if model.acts_as_mochigome_focus?
          opts = model.mochigome_focus_settings.options
          ignore_assocs = opts[:ignore_assocs]
          model_preferred_paths = opts[:preferred_paths]
        end

        preferred_paths = {}

        # Use through reflections as a hint for preferred indirect paths
        # TODO Support for nested through reflections
        # (Though Rails 2 doesn't support them either...)
        model.reflections.select{|name, assoc| assoc.through_reflection}.
        reject{|name, assoc| ignore_assocs.include? name.to_sym}.
        reject{|name, assoc| ignore_assocs.include? assoc.through_reflection.name.to_sym}.
        to_a.sort{|a,b| a.first.to_s <=> b.first.to_s}.
        each do |name, assoc|
          begin
            foreign_model = assoc.klass
            join_model = assoc.through_reflection.klass
          rescue NameError
            # FIXME Can't handle polymorphic through reflection
          end
          edge = [model, foreign_model]
          path = [model, join_model, foreign_model]
          next if @shortest_paths[edge].try(:size).try(:<, path.size)
          preferred_paths[edge] = path
        end

        # Model focus can specify paths with prefered_path_to
        model_preferred_paths.each do |tgt_model_name, assoc_name|
          tgt_model = tgt_model_name.constantize
          edge = [model, tgt_model]
          assoc = model.reflections[assoc_name]
          sub_path = @shortest_paths[[assoc.klass, tgt_model]]
          unless sub_path
            raise ModelSetupError.new(
              "Can't find subpath to #{tgt_model} via #{model.name}.#{assoc_name}"
            )
          end
          if sub_path.include?(model)
            raise ModelSetupError.new(
              "Subpath to #{tgt_model} via #{model.name}.#{assoc_name} loops back"
            )
          end
          sub_link = @shortest_paths[[model, assoc.klass]]
          preferred_paths[edge] = sub_link + sub_path.drop(1)
        end

        # Replace all instances of the default path in the path directory
        # with the preferred path, including when the default path is
        # a subset of a larger path, and/or when the direction of travel
        # is reversed.
        # FIXME What if preferred paths conflict?
        # FIXME What if one preferred path causes a shortest_path to become
        # applicable under another one? Then arbitrary model scanning
        # order matters, and it shouldn't. Is there even a consistent
        # way to deal with this?
        preferred_paths.each do |edge, path|
          [lambda{|a| a}, lambda{|a| a.reverse}].each do |prc|
            e, p = prc.call(edge), prc.call(path)
            old_path = @shortest_paths[e]
            next if old_path == p
            edges_to_replace = {}
            @shortest_paths.each do |se, sp|
              p_begin = sp.find_index(old_path.first)
              if p_begin && sp[p_begin, old_path.size] == old_path
                edges_to_replace[se] =
                  sp.take(p_begin) +
                  p +
                  sp.drop(p_begin + old_path.size)
              end
            end
            edges_to_replace.each do |re, rp|
              @shortest_paths[re] = rp
            end
          end
        end
      end
    end
  end
end
