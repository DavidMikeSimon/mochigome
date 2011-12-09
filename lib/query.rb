require 'rgl/adjacency'
require 'rgl/traversal'

module Mochigome
  class Query
    def initialize(layer_types, name = "report")
      # TODO: Validate layer types: not empty, AR, act_as_mochigome_focus, graph correctly, no repeats
      @layer_types = layer_types
      @name = name
    end

    def run(objs)
      objs = [objs] unless objs.is_a?(Enumerable)
      return DataNode.new(:report, @name) if objs.size == 0 # Empty DataNode for empty input

      # TODO: Theoretically we could limit on multiple types at once, right?
      unless objs.all?{|obj| obj.class == objs.first.class}
        raise QueryError.new("Query target objects must all be the same type")
      end

      unless @layer_types.any?{|layer| objs.first.is_a?(layer)}
        raise QueryError.new("Query target object type must be in the query layer list")
      end

      # Used to provide debugging information in the root DataNode comment
      assoc_path = ["== #{objs.first.class.name} =="]

      # Start at the layer for objs, and descend downwards through layers after that
      #TODO: It would be really fantastic if I could just use AR eager loading for this
      downwards_layers = @layer_types.drop_while{|cls| !objs.first.is_a?(cls)}
      root = DataNode.new(:report, @name)
      root << objs.map{|obj| DataNode.new(
        obj.mochigome_focus.type_name,
        obj.mochigome_focus.name,
        [{:obj => obj}]
      )}
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
              subnode = datanode << build_node(
                {:obj => obj, :through_obj => through_obj}
              )
              new_layer << subnode
            end
          else
            #FIXME: Not DRY
            datanode[:obj].send(assoc.name).each do |obj|
              subnode = datanode << build_node({:obj => obj})
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
          if assoc.through_reflection
            through_objs = child[:obj].send(assoc.through_reflection.name)
            through_objs = [through_objs] unless through_objs.is_a?(Enumerable)
            through_objs.each do |through_obj|
              # TODO: Don't assume that through means singular!
              parent = through_obj.send(assoc.source_reflection.name)
              unless parent_children_map.has_key?(parent.id)
                attrs = {:obj => parent, :through_obj => through_obj}
                parent_children_map[parent.id] = build_node(attrs)
              end
              parent_children_map[parent.id] << child.dup
            end
          else
            #FIXME: Not DRY
            parents = child[:obj].send(assoc.name)
            parents = [parents] unless parents.is_a?(Enumerable)
            parents.each do |parent|
              unless parent_children_map.has_key?(parent.id)
                attrs = {:obj => parent}
                parent_children_map[parent.id] = build_node(attrs)
              end
              parent_children_map[parent.id] << child.dup
            end
          end
        end

        root = DataNode.new(:report, @name)
        root << parent_children_map.values
      end

      root.comment = <<-eos
        Mochigome Version: #{Mochigome::VERSION}
        Time: #{Time.now}
        Layers: #{@layer_types.map(&:name).join(" => ")}
        AR Association Path:
        #{assoc_path.map{|s| "* #{s}"}.join("\n")}
      eos
      root.comment.gsub!(/\n +/, "\n")
      root.comment.lstrip!

      focus_data_node_objs(root)
      return root
    end

    private

    def build_node(attrs)
      focus = attrs[:obj].mochigome_focus
      DataNode.new(focus.name, focus.type_name, attrs)
    end

    def focus_data_node_objs(node, obj_stack=[], commenting=true)
      pushed = 0
      if node.has_key?(:obj)
        obj = node.delete(:obj)
        if node.has_key?(:through_obj)
          obj_stack.push(node.delete(:through_obj)); pushed += 1
        end
        obj_stack.push(obj); pushed += 1
        if commenting
          node.comment = <<-eos
            Context:
            #{obj_stack.map{|o| "#{o.class.name}:#{o.id}"}.join("\n")}
          eos
          node.comment.gsub!(/\n +/, "\n")
          node.comment.lstrip!
        end
        node.merge!(obj.mochigome_focus.data(:context => obj_stack))
        node[:internal_type] = obj.class.name
      end
      node.children.each_index do |i|
        focus_data_node_objs(node.children[i], obj_stack, i == 0 && commenting)
      end
      pushed.times{ obj_stack.pop }
    end

    @@assoc_graph = RGL::DirectedAdjacencyGraph.new
    @@graphed_models = Set.new
    @@edge_relation_funcs = {}
    @@shortest_paths = {}

    def self.ids_relation_over_path(path)
      rel = Arel::Table.new(path.first.table_name)
      (0..(path.size-2)).each do |i|
        u = path[i]
        v = path[i+1]
        f = @@edge_relation_funcs[[u,v]]
        raise QueryError.new("No association from #{u.name} to #{v.name}") unless f
        rel = f.call(rel)
      end
      rel.project(path.map{|m| Arel::Table.new(m.table_name)[m.primary_key]})
    end

    def self.path_thru(models)
      update_assoc_graph(models.reject{|m| @@assoc_graph.has_vertex?(m)})
      path = [models.first]
      (0..(models.size-2)).each do |i|
        u = models[i]
        v = models[i+1]
        seg = @@shortest_paths[[u,v]]
        raise QueryError.new("Can't travel from #{u.name} to #{v.name}") unless seg
        seg.drop(1).each{|step| path << step}
      end
      unless path.uniq == path
        raise QueryError.new("Path thru #{models.map(&:name).join('-')} doubles back: #{path.map(&:name).join('-')}")
      end
      path
    end

    def self.update_assoc_graph(models)
      model_queue = models.dup
      added_models = []
      until model_queue.empty?
        model = model_queue.shift
        next if @@graphed_models.include? model
        @@graphed_models.add model
        added_models << model

        model.reflections.each do |name, assoc|
          next if assoc.through_reflection
          next if assoc.options[:polymorphic] # How to deal with these? Check for matching has_X assoc?
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
        path_tree = @@assoc_graph.bfs_search_tree_from(model).reverse
        path_tree.depth_first_search do |tgt_model|
          next if tgt_model == model
          path = [tgt_model]
          while (parent = path_tree.adjacent_vertices(path.first).first)
            path.unshift parent
          end
          @@shortest_paths[[model,tgt_model]] = path
        end
      end
    end
  end
end
