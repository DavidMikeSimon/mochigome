require 'active_support'

module Mochigome
  class DataNode < ActiveSupport::OrderedHash
    attr_accessor :type_name
    attr_accessor :name
    attr_accessor :comment
    attr_reader :children

    def initialize(type_name, name, content = [])
      # Convert content keys to symbols
      super()
      self.merge!(content)
      @type_name = type_name.to_s
      @name = name.to_s
      @comment = nil
      @children = []
    end

    def merge!(a)
      if a.is_a?(Array)
        a.each do |h|
          self[h.keys.first.to_sym] = h.values.first
        end
      else
        super
      end
    end

    def <<(item)
      if item.is_a?(Array)
        item.map {|i| self << i}
      else
        raise DataNodeError.new("New child #{item} is not a DataNode") unless item.is_a?(DataNode)
        @children << item
        @children.last
      end
    end

    def /(idx)
      @children[idx]
    end

    def clone
      twin = super
      twin.instance_variable_set(:@children, @children.map{|c| c.clone})
      twin
    end

    # TODO: Only define xml-related methods if nokogiri loaded
    def to_xml
      doc = Nokogiri::XML::Document.new
      append_xml_to(doc)
      doc
    end

    # TODO: Only define ruport-related methods if ruport is loaded
    def to_flat_ruport_table
      col_names = flat_column_names
      table = Ruport::Data::Table.new(:column_names => col_names)
      append_rows_to(table, col_names.size)
      table
    end

    def to_flat_arrays
      table = []
      col_names = flat_column_names
      table << col_names
      append_rows_to(table, col_names.size)
      table
    end

    private

    def append_xml_to(x)
      doc = x.document
      node = Nokogiri::XML::Node.new("node", doc)
      node["type"] = @type_name.titleize
      node["name"] = @name
      [:id, :internal_type].each do |attr|
        node[attr.to_s] = delete(attr).to_s if has_key?(attr)
      end
      node.add_child(Nokogiri::XML::Comment.new(doc, @comment)) if @comment
      each do |key, value|
        sub_node = Nokogiri::XML::Node.new("datum", doc)
        sub_node["name"] = key.to_s.titleize
        sub_node.content = value
        node.add_child(sub_node)
      end
      @children.each do |child|
        child.send(:append_xml_to, node)
      end
      x.add_child(node)
    end

    # TODO: Should handle trickier situations involving datanodes not having various columns
    def flat_column_names
      colnames = (["name"] + keys).map {|key| "#{@type_name}::#{key}"}
      choices = @children.map(&:flat_column_names)
      colnames += choices.max_by(&:size) || []
      colnames
    end

    # TODO: Should handle trickier situations involving datanodes not having various columns
    def append_rows_to(table, pad, stack = [])
      stack.push([@name] + values)
      if @children.size > 0
        @children.each {|child| child.send(:append_rows_to, table, pad, stack)}
      else
        row = stack.flatten(1)
        table << (row + Array.new(pad - row.size, nil))
      end
      stack.pop
    end
  end
end
