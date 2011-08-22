require 'rgl/adjacency'

module Ernie
  class Aggregator
    def initialize(layer_types)
      # TODO: Validate layer types: must act_as_report_focus, graph correctly, no repeats
      @layer_types = layer_types
    end

    def focused_on(objs)
      objs = [objs] unless objs.is_a?(Enumerable)
      return DataSet.new(@layer_types) if objs.size == 0 # Empty DataSet for empty input
      # TODO: Test for invalid objs (all objs not same type or not a layer type)

      # Start at the layer for objs, and descend downwards through layers after that
      downwards_layers = @layer_types.drop_while{|cls| !objs.first.is_a?(cls)}
      root = DataSet.new(downwards_layers)
      cur_layer = root << objs
      downwards_layers.drop(1).each do |cls|
        assoc = Aggregator.edge_assoc(cur_layer.first.content.class, cls)
        results = cur_layer.map do |dataset|
          dataset << dataset.content.send(assoc[:name])
        end
        cur_layer = results.flatten # In case it's a to-many assoc
      end

      # Take our tree so far and include it in parent trees, going up to the first layer
      upwards_layers = @layer_types.take_while{|cls| !objs.first.is_a?(cls)}.reverse
      upwards_layers.each do |cls|
        assoc = Aggregator.edge_assoc(root.children.first.content.class, cls)
        parent_children_map = {} # Key is parent ID, value is dataset with parent content
        root.children.each do |child|
          parents = child.content.send(assoc[:name])
          parents = [parents] unless parents.is_a?(Enumerable)
          parents.each do |parent|
            parent_children_map[parent.id] = DataSet.new(
              root.layer_types.dup, parent
            ) unless parent_children_map.has_key?(parent.id)
            parent_children_map[parent.id] << child
          end
        end
        downwards_layers.unshift(cls)
        root = DataSet.new(downwards_layers)
        root << parent_children_map.values
      end

      return root
    end

    private

    @@assoc_graph = nil
    @@edge_assocs = {}

    def self.assoc_graph
      return @@assoc_graph if @assoc_graph

      # Build a directed graph of the associations between focusable models
      @@assoc_graph = RGL::DirectedAdjacencyGraph.new
      @@assoc_graph.add_vertices(*Ernie::reportFocusModels)
      Ernie::reportFocusModels.each do |cls|
        # Add any associations that lead to other reportFocusModels
        cls.reflections.each do |name, assoc|
          if Ernie::reportFocusModels.include?(assoc.klass)
            @@assoc_graph.add_edge(cls, assoc.klass)
            # Also keep track of the association details for each edge
            @@edge_assocs[[cls, assoc.klass]] = {:name => name, :assoc => assoc}
          end
        end
      end
      return @@assoc_graph
    end

    def self.edge_assoc(u, v)
      assoc_graph # Make sure @@edge_assocs has been populated
      assoc = @@edge_assocs[[u,v]]
      raise AggregationError.new(
        "No association between #{u} and #{v}"
      ) unless assoc
      return assoc
    end
  end
end
