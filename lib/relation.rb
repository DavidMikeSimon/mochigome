module Mochigome
  private

  class Relation
    attr_reader :joins, :spine_layers

    def initialize(layers)
      @model_graph = ModelGraph.new
      @spine_layers = layers
      @models = Set.new
      @model_join_stack = []
      @spine = []
      @joins = []

      @spine_layers.map(&:to_real_model).uniq.each do |m|
        if @rel
          join_to_model(m)
        else
          @rel = @model_graph.relation_init(m)
          @models.add m
        end
        @spine << m
      end
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
      c.instance_variable_set :@models, @models.clone
      c.instance_variable_set :@rel, @rel.clone
      c
    end

    def join_to_model(model)
      return if @models.include?(model)

      # Route to it in as few steps as possible, closer to spine end if tie.
      best_path = nil
      (@spine.reverse + (@models.to_a - @spine).sort{|a,b| a.name <=> b.name}).each do |link_model|
        path = @model_graph.path_thru([link_model, model])
        if path && (best_path.nil? || path.size < best_path.size)
          best_path = path
        end
      end

      raise QueryError.new("No path to #{model}") unless best_path
      join_on_path(best_path)

      # Also use the conditions of any other direct assoc to the target
      # TODO: Or maybe any other assoc that's equal length?
      # TODO: Write a test that requires the below code to work
      @models.reject{|n| best_path.include?(n)}.each do |n|
        cond = @model_graph.edge_condition(n, model)
        if cond
          @rel = @rel.where(cond)
        end
      end
    end

    def join_on_path_thru(path)
      full_path = @model_graph.path_thru(path).uniq
      if full_path
        join_on_path(full_path)
      else
        raise QueryError.new("Cannot route thru #{path.map(&:name).inspect}")
      end
    end

    def join_on_path(path)
      path = path.map(&:to_real_model).uniq
      join_to_model path.first
      (0..(path.size-2)).map{|i| [path[i], path[i+1]]}.each do |src, tgt|
        add_join_link(src, tgt) unless @models.include?(tgt)
      end
    end

    def select_model_id(m)
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

      @model_join_stack.push tgt
      begin
        cond = @model_graph.edge_condition(src, tgt)
        join_to_expr_models(cond)
        @rel = @rel.join(tgt.arel_table, Arel::Nodes::InnerJoin).on(cond)
      ensure
        @model_join_stack.pop
      end

      @joins << [src, tgt]
      @models.add tgt
    end

    def join_to_expr_models(expr)
      @model_graph.expr_models(expr).each do |m|
        join_to_model(m) unless @model_join_stack.include?(m)
      end
    end
  end
end
