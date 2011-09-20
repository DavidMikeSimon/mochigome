require 'active_support'

module Mochigome
  class DataNode < ActiveSupport::OrderedHash
    attr_accessor :type_name
    attr_accessor :comment
    attr_reader :children

    def initialize(type_name, content = [])
      # Convert content keys to symbols
      super()
      type_name = type_name.to_sym
      self.merge!(content)
      @type_name = type_name
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

    # TODO: Only define xml-related methods if nokogiri loaded
    def to_xml
      doc = Nokogiri::XML::Document.new
      append_xml_to(doc)
      doc
    end

    # TODO: Only define ruport-related methods if ruport is loaded
    def to_ruport_table
      table = Ruport::Data::Table.new(:column_names => flat_column_names)
      append_rows_to(table)
      table
    end

    private

    def append_xml_to(x)
      doc = x.document
      node = Nokogiri::XML::Node.new(@type_name.to_s.camelize(:lower), doc)
      node["id"] = self[:id].to_s if has_key?(:id)
      node.add_child(Nokogiri::XML::Comment.new(doc, @comment)) if @comment
      each do |key, value|
        next if key == 'id'
        sub_node = Nokogiri::XML::Node.new(key.to_s.camelize(:lower), doc)
        sub_node.content = value
        node.add_child(sub_node)
      end
      @children.each {|child| child.send(:append_xml_to, node)}
      x.add_child(node)
    end

    def flat_column_names
      colnames = keys.map {|key| "#{@type_name}::#{key}"}
      if @children.size > 0
        # All children should have the same content keys
        colnames += @children.first.send(:flat_column_names)
      end
      colnames
    end

    def append_rows_to(table, stack = [])
      stack.push values
      if @children.size > 0
        @children.each {|child| child.send(:append_rows_to, table, stack)}
      else
        table << stack.flatten(1)
      end
      stack.pop
    end
  end
end
