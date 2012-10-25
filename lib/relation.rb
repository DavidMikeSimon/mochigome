module Mochigome
  private

  class Relation
    attr_reader :spine_layers, :join_path_descriptions

    def initialize(layers)
      @model_graph = ModelGraph.new
      @spine_layers = layers
      @models = Set.new
      @model_join_stack = []
      @spine = []
      @join_path_descriptions = []

      @spine_layers.map(&:to_real_model).uniq.each do |m|
        join_to_model(m)
        @spine << m
      end
      @spine_layers.each{|m| select_model_id(m)}
    end

    def to_arel
      @rel.try(:clone)
    end

    def to_sql
      @rel.try(:to_sql)
    end

    def clone
      c = super
      c.instance_variable_set :@models, @models.clone
      c.instance_variable_set :@rel, @rel.clone if @rel
      c
    end

    def join_to_model(model)
      return if @models.include?(model)
      unless @rel
        @rel = @model_graph.relation_init(model)
        @models.add model
        return
      end

      # Route to it in as few steps as possible, closer to spine end if tie.
      best_path = nil
      (@spine.reverse + (@models.to_a - @spine).sort{|a,b| a.name <=> b.name}).each do |link_model|
        path = @model_graph.path_thru([link_model, model])
        if path && (best_path.nil? || path.size < best_path.size)
          best_path = path
        end
      end

      raise QueryError.new("No path to #{model} from #{@models.map(&:name).inspect}") unless best_path
      join_on_path best_path, "Best path to model #{model}"

      # Also use the conditions of any other unique path
      # TODO: Write a test that requires the below code to work
      @models.reject{|n| best_path.include?(n)}.each do |n|
        extra_path = @model_graph.path_thru([n, model])
        if extra_path
          unless best_path.all?{|m| extra_path.include?(m)}
            join_on_path extra_path, "Additional path to model #{model}"
          end
        end
      end
    end

    def join_on_path_thru(path, descrip = nil)
      full_path = @model_graph.path_thru(path)
      if full_path
        join_on_path(full_path, descrip || "Generic path thru #{path.map(&:name).inspect}")
      else
        raise QueryError.new("Cannot route thru #{path.map(&:name).inspect}")
      end
    end

    def join_on_path(path, descrip = "Generic")
      begin
        path = path.map(&:to_real_model).uniq
        join_to_model path.first
        join_descrips = [path.first.name]
        (0..(path.size-2)).map{|i| [path[i], path[i+1]]}.each do |src, tgt|
          if @models.include?(tgt)
            apply_condition(@model_graph.edge_condition(src, tgt))
            join_descrips << "*#{tgt.name}"
          else
            add_join_link(src, tgt)
            join_descrips << tgt.name
          end
        end
        @join_path_descriptions << "#{join_descrips.join("->")} (#{descrip})"
      rescue QueryError => e
        raise QueryError.new("Error pathing #{path.map(&:name).inspect}: #{e}")
      end
    end

    def select_model_id(m)
      join_to_model(m)
      @rel = @rel.project(m.arel_primary_key.as("#{m.name}_id"))
    end

    def select_expr(e)
      join_to_expr_models(e)
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

      join_to_expr_models(cond)
      @rel = @rel.where(cond)
    end

    def apply_access_filter_func(func)
      @models.each do |m|
        begin
          h = func.call(m)
          h.delete(:join_paths).try :each do |path|
            # FIXME: Eventually we need to support joins that
            # double back, if only for CanCan stuff, so get rid of this
            # uniq junk.
            join_on_path_thru path.uniq, "Access filter for #{m.name}"
          end
          if h[:condition]
            apply_condition h.delete(:condition)
          end
          unless h.empty?
            raise QueryError.new("Unknown assoc filter keys #{h.keys.inspect}")
          end
        rescue QueryError => e
          raise QueryError.new("Error checking access to #{m.name}: #{e}")
        end
      end
    end

    private

    def add_join_link(src, tgt)
      raise QueryError.new("Can't join from #{src}, not available") unless
        @models.include?(src)

      @model_join_stack.push tgt
      begin
        cond = @model_graph.edge_condition(src, tgt) or
          raise QueryError.new("No direct link from #{src} to #{tgt}")
        join_to_expr_models(cond)
        @rel = @rel.join(tgt.arel_table, Arel::Nodes::InnerJoin).on(cond)
      ensure
        @model_join_stack.pop
      end

      @models.add tgt
    end

    def join_to_expr_models(expr)
      @model_graph.expr_models(expr).each do |m|
        join_to_model(m) unless @model_join_stack.include?(m)
      end
    end
  end
end
