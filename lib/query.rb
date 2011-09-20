require 'rgl/adjacency'

module Mochigome
  class Query
    def initialize(layer_types, name = "report")
      # TODO: Validate layer types: not empty, AR, act_as_mochigome_focus, graph correctly, no repeats
      @layer_types = layer_types
      @name = name
    end

    def run(objs)
      objs = [objs] unless objs.is_a?(Enumerable)
      return DataNode.new(@name) if objs.size == 0 # Empty DataNode for empty input
      # TODO: Test for invalid objs (not all objs same type or not a layer type)

      # Used to provide debugging information in the root DataNode comment
      assoc_path = ["== #{objs.first.class.name} =="]

      # Start at the layer for objs, and descend downwards through layers after that
      #TODO: It would be really fantastic if I could just use AR eager loading for this
      downwards_layers = @layer_types.drop_while{|cls| !objs.first.is_a?(cls)}
      root = DataNode.new(@name)
      root << objs.map{|obj| DataNode.new(obj.class.name, [{:obj => obj}])}
      cur_layer = root.children
      downwards_layers.drop(1).each do |cls|
        new_layer = []
        assoc = Query.edge_assoc(cur_layer.first[:obj].class, cls)

        assoc_str = "-> #{cls.name} via #{cur_layer.first[:obj].class.name}##{assoc.name}"
        if assoc.through_reflection
          assoc_str << " (thru #{assoc.through_reflection.name})"
        end
        assoc_path.push assoc_str

        cur_layer.each do |datanode|
          # FIXME: Don't assume that downwards means plural association
          # TODO: Are there other ways context could matter besides :through assocs?
          # i.e. If C belongs_to A and also belongs_to B, and layer_types = [A,B,C]
          # TODO: What if a through reflection goes through _another_ through reflection?
          if assoc.through_reflection
            datanode[:obj].send(assoc.through_reflection.name).each do |through_obj|
              # TODO: Don't assume that through means singular!
              obj = through_obj.send(assoc.source_reflection.name)
              subnode = datanode << DataNode.new(
                obj.class.name, [{:obj => obj}, {:through_obj => through_obj}]
              )
              new_layer << subnode
            end
          else
            #FIXME: Not DRY
            datanode[:obj].send(assoc.name).each do |obj|
              subnode = datanode << DataNode.new(obj.class.name, [{:obj => obj}])
              new_layer << subnode
            end
          end
        end
        cur_layer = new_layer
      end

      # Take our tree so far and include it in parent trees, going up to the first layer
      upwards_layers = @layer_types.take_while{|cls| !objs.first.is_a?(cls)}.reverse
      upwards_layers.each do |cls|
        assoc = Query.edge_assoc(root.children.first[:obj].class, cls)

        assoc_str =  "<- #{cls.name} via #{root.children.first[:obj].class.name}##{assoc.name}"
        if assoc.through_reflection
          assoc_str << " (thru #{assoc.through_reflection.name})"
        end
        assoc_path.unshift assoc_str

        parent_children_map = ActiveSupport::OrderedHash.new
        root.children.each do |child|
          parents = child[:obj].send(assoc.name)
          parents = [parents] unless parents.is_a?(Enumerable)
          parents.each do |parent|
            unless parent_children_map.has_key?(parent.id)
              attrs = [{:obj => parent}]
              if assoc.through_reflection
                attrs << {:through_obj => child[:obj].send(assoc.through_reflection.name)}
              end
              parent_children_map[parent.id] = DataNode.new(parent.class.name, attrs)
            end
            parent_children_map[parent.id] << child
          end
        end
        root = DataNode.new(@name)
        root << parent_children_map.values
      end

      root.comment = <<-eos

        Mochigome Version: #{Mochigome::VERSION}
        Query Ran: #{Time.now}
        Layers: #{@layer_types.map(&:name).join(" => ")}
        AR Association Path:
        #{assoc_path.map{|s| "* #{s}"}.join("\n")}
      eos
      root.comment.gsub!(/\n +/, "\n")
      focus_data_node_objs(root)
      return root
    end

    private

    def focus_data_node_objs(node, obj_stack=[])
      pushed = 0
      if node.has_key?(:obj)
        obj = node.delete(:obj)
        obj_stack.push(obj); pushed += 1
        if node.has_key?(:through_obj)
          obj_stack.push(node.delete(:through_obj)); pushed += 1
        end
        node.merge!(obj.mochigome_focus.data(:context => obj_stack))
      end
      node.children.each {|c| focus_data_node_objs(c)}
      pushed.times{ obj_stack.pop }
    end

    @@assoc_graph = nil
    @@edge_assocs = {}

    def self.assoc_graph
      return @@assoc_graph if @assoc_graph

      # Build a directed graph of the associations between focusable models
      @@assoc_graph = RGL::DirectedAdjacencyGraph.new
      @@assoc_graph.add_vertices(*Mochigome::reportFocusModels)
      Mochigome::reportFocusModels.each do |cls|
        # Add any associations that lead to other reportFocusModels
        cls.reflections.each do |name, assoc|
          if Mochigome::reportFocusModels.include?(assoc.klass)
            @@assoc_graph.add_edge(cls, assoc.klass)
            @@edge_assocs[[cls, assoc.klass]] = assoc
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
