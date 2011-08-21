require 'rgl/adjacency'

module Ernie
  class Aggregator
    def initialize(layers)
      # TODO: Validate layers just as DataSet.initialize does
      @layers = layers
    end

    def focused_on(obj)
      # TODO: Test for obj of invalid type (i.e. no layer, not ActiveRecord, etc)
      focus_layer_idx = @layers.find{|cls| obj.is_a?(cls)}

      root_dataset = DataSet.new(@layers)
      cur = root_dataset
      @layers.each do |cls|
        if obj.is_a?(cls)
          cur = cur << obj
        else
          assoc = Aggregator.edge_assoc(obj.class, cls)
          cur = cur << obj.send(assoc[:name])
        end
      end

      return root_dataset
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
      return @@edge_assocs[[u,v]]
    end
  end
end
