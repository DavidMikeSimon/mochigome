module Ernie
  class DataNode
    include Enumerable

    attr_accessor :content
    attr_reader :layer_types
    attr_reader :children

    def initialize(layer_types, content = nil)
      @layer_types = layer_types
      @content = content
      @children = []
    end
    delegate :each, :size, :empty?, :to => :@children

    def <<(item)
      if item.is_a?(Array)
        item.map {|i| self << i}
      else
        if item.is_a?(DataNode)
          unless item.content.is_a?(@layer_types.first)
            raise LayerMismatchError.new(
              "Need a #{@layer_types.first.name} but got a DataNode of #{item.class.name}"
            )
          end
          unless item.layer_types == @layer_types.drop(1)
            raise LayerMismatchError.new(
              "Got a child DataNode with non-matching child layers, expected #{@layer_types.drop(1).inspect}, got #{item.layer_types.inspect}"
            )
          end
          child_node = item
        else
          unless item.is_a?(@layer_types.first)
            raise LayerMismatchError.new(
              "Need a #{@layer_types.first.name} but got a #{item.class.name}"
            )
          end
          child_node = DataNode.new(@layer_types.drop(1), item)
        end
        @children << child_node
        @children.last
      end
    end

    def [](term)
      case term
      when Integer then @children[term]
      when ActiveRecord::Base
        unless term.is_a?(@layer_types.first)
          raise LayerMismatchError.new "Need a #{@layer_types.first.name} but got a #{term.class.name}"
        end
        idx = @children.index{|c| c.content == term}
        idx ? @children[idx] : nil
      else raise ArgumentError.new("DataNode#[] requires an integer or a ActiveRecord")
      end
    end

    def children_content
      @children.map(&:content)
    end

    def to_xml
      xml = Builder::XmlMarkup.new
      xml.tag! "data" do
        append_xml_to(xml)
      end
      xml
    end

    def to_ruport_table
      table = Ruport::Data::Table.new(:column_names => flat_column_names)
      append_rows_to(table)
      table
    end

    private

    def append_xml_to(x)
      if content
        focus = content.report_focus
        x.tag!(focus.group_name.camelize(:lower), {:recId => content.id}) do
          (focus.data + focus.aggregate_data(:all)).each do |field|
            x.tag!(field[:name].camelize(:lower), field[:value])
          end
          append_children_to x
        end
      else
        append_children_to x
      end
    end

    def append_children_to(x)
      @children.each {|child| child.send(:append_xml_to, x)}
    end

    def flat_column_names
      if @content
        focus = @content.report_focus
        colnames = focus.data.map{|f| "#{focus.group_name}::#{f[:name]}"}
        colnames += focus.aggregate_data(:all).map{|f| "#{focus.group_name}::#{f[:name]}"}
      else
        colnames = []
      end
      if @children.size > 0
        colnames += @children.first.send(:flat_column_names)
      end
      colnames
    end

    def append_rows_to(table, stack = [])
      if @content
        focus = @content.report_focus
        stack.push ((focus.data + focus.aggregate_data(:all)).map{|r| r[:value]})
      end
      if @children.size > 0
        @children.each {|child| child.send(:append_rows_to, table, stack)}
      else
        table << stack.flatten(1)
      end
      stack.pop if @content
    end
  end
end
