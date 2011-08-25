require 'rgl/adjacency'

module Ernie
  class Query
    def initialize(layer_types, name = "report")
      # TODO: Validate layer types: not empty, act_as_report_focus, graph correctly, no repeats
      @layer_types = layer_types
      @name = name
    end

    def run(objs)
      objs = [objs] unless objs.is_a?(Enumerable)
      return DataNode.new(@name) if objs.size == 0 # Empty DataNode for empty input
      # TODO: Test for invalid objs (all objs not same type or not a layer type)

      # Start at the layer for objs, and descend downwards through layers after that
      downwards_layers = @layer_types.drop_while{|cls| !objs.first.is_a?(cls)}
      root = DataNode.new(@name)
      root << objs.map{|obj| DataNode.new(obj.class.name, [{:obj => obj}])}
      cur_layer = root.children
      downwards_layers.drop(1).each do |cls|
        new_layer = []
        assoc = Query.edge_assoc(cur_layer.first[:obj].class, cls)
        cur_layer.each do |datanode|
          # FIXME: Don't assume that downards means plural association
          datanode[:obj].send(assoc[:name]).each do |obj|
            subnode = datanode << DataNode.new(obj.class.name, [{:obj => obj}])
            new_layer << subnode
          end
        end
        cur_layer = new_layer
      end

      # Take our tree so far and include it in parent trees, going up to the first layer
      upwards_layers = @layer_types.take_while{|cls| !objs.first.is_a?(cls)}.reverse
      upwards_layers.each do |cls|
        assoc = Query.edge_assoc(root.children.first[:obj].class, cls)
        parent_children_map = ActiveSupport::OrderedHash.new
        root.children.each do |child|
          parents = child[:obj].send(assoc[:name])
          parents = [parents] unless parents.is_a?(Enumerable)
          parents.each do |parent|
            parent_children_map[parent.id] = DataNode.new(
              parent.class.name, [{:obj => parent}]
            ) unless parent_children_map.has_key?(parent.id)
            parent_children_map[parent.id] << child
          end
        end
        root = DataNode.new(@name)
        root << parent_children_map.values
      end

      focus_data_node_objs(root)
      return root
    end

    private

    def focus_data_node_objs(node, obj_stack=[])
      # TODO: As possible contexts, also need to include join models skipped by :through
      pushed = false
      if node.has_key?(:obj)
        obj = node.delete(:obj)
        node.merge!(obj.report_focus.data(:context => obj_stack))
        obj_stack.push(obj)
        pushed = true
      end
      node.children.each {|c| focus_data_node_objs(c)}
      obj_stack.pop if pushed
    end

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
      raise QueryError.new(
        "No association between #{u} and #{v}"
      ) unless assoc
      return assoc
    end
  end
end
