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
      elsif item.is_a?(DataNode)
        @children << item
        @children.last
      else
        raise DataNodeError.new("Can't adopt #{item.inspect}, it's not a DataNode")
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

    def to_xml
      doc = Nokogiri::XML::Document.new
      append_xml_to(doc)
      doc
    end

    def to_flat_ruport_table
      col_names = flat_column_names
      table = Ruport::Data::Table.new(:column_names => col_names)
      append_rows_to(table, col_names)
      table
    end

    def to_flat_arrays
      table = []
      col_names = flat_column_names
      table << col_names
      append_rows_to(table, col_names)
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
        if key.to_s.start_with?("_")
          sub_node = Nokogiri::XML::Node.new(key.to_s.sub("_", ""), doc)
        else
          sub_node = Nokogiri::XML::Node.new("datum", doc)
          sub_node["name"] = key.to_s.titleize
        end
        sub_node.content = value
        node.add_child(sub_node)
      end
      @children.each do |child|
        child.send(:append_xml_to, node)
      end
      x.add_child(node)
    end

    def flat_column_names
      colnames = (["name"] + keys).
        reject{|key| key.to_s.start_with?("_")}.
        map{|key| "#{@type_name}::#{key}"}
      choices = @children.map(&:flat_column_names)
      colnames += choices.flatten(1).uniq || []
      colnames
    end

    def append_rows_to(table, colnames, row = nil)
      row = colnames.map{nil} if row.nil?

      added_cell_indices = []
      colnames.each_with_index do |k, i|
        if k =~ /^#{@type_name}::(.+)$/
          attr_name = $1
          if attr_name.to_sym == :name
            row[i] = name
          else
            row[i] = self[attr_name.to_sym]
          end
          added_cell_indices << i
        end
      end

      if @children.size > 0
        @children.each {|child| child.send(:append_rows_to, table, colnames, row)}
      else
        table << row.dup
      end

      added_cell_indices.each{|i| row[i] = nil}
    end
  end
end
