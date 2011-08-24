require 'active_support'

module Ernie
  def self.hash_with_symbol_keys(h)
    r = {}
    h.each{|k,v| r[k.to_sym] = v}
    r
  end

  class DataNode < ActiveSupport::OrderedHash
    attr_accessor :type_name
    attr_reader :children

    def initialize(type_name, content = {})
      # Convert content keys to symbols
      # TODO Can I do this better with some kind of OrderedHashWithIndifferentAccess?
      type_name = type_name.to_sym
      unless content.keys.all?{|k| k.is_a?(Symbol)}
        content = Ernie::hash_with_symbol_keys(content)
      end
      self.replace(content)
      @type_name = type_name
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
      xml = Builder::XmlMarkup.new
      append_xml_to(xml)
      xml
    end

    # TODO: Only define ruport-related methods if ruport is loaded
    def to_ruport_table
      table = Ruport::Data::Table.new(:column_names => flat_column_names)
      append_rows_to(table)
      table
    end

    private

    def append_xml_to(x)
      x.tag!(@type_name.to_s.camelize(:lower), has_key?(:id) ? {:id => self[:id]} : {}) do
        each {|key, value| x.tag!(key.to_s.camelize(:lower), value)}
        @children.each {|child| child.send(:append_xml_to, x)}
      end
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
