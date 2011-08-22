module Ernie
  class DataSet
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

    def clone
      tgt = DataSet.new(@layer_types, @content)
      tgt.instance_variable_set(:@children, @children)
      tgt
    end

    def <<(item)
      if item.is_a?(Array)
        item.map {|i| self << i}
      else
        if item.is_a?(DataSet)
          unless item.content.is_a?(@layer_types.first)
            raise LayerMismatchError.new(
              "Need a #{@layer_types.first.name} but got a DataSet of #{item.class.name}"
            )
          end
          unless item.layer_types == @layer_types.drop(1)
            raise LayerMismatchError.new(
              "Got a child DataSet with non-matching child layers, expected #{@layer_types.drop(1).inspect}, got #{item.layer_types.inspect}"
            )
          end
          child_node = item
        else
          unless item.is_a?(@layer_types.first)
            raise LayerMismatchError.new(
              "Need a #{@layer_types.first.name} but got a #{item.class.name}"
            )
          end
          child_node = DataSet.new(@layer_types.drop(1), item)
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
      else raise ArgumentError.new("DataSet#[] requires an integer or a ActiveRecord")
      end
    end

    def children_content
      @children.map(&:content)
    end

    def to_xml
      xml = Builder::XmlMarkup.new
      xml.tag! "dataSet" do
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
          focus.data.each do |field|
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
      else
        colnames = []
      end
      if @children.size > 0
        colnames += @children.first.send(:flat_column_names)
      end
      colnames
    end

    def append_rows_to(table, stack = [])
      stack.push @content.report_focus.data.map{|r| r[:value]} if @content
      if @children.size > 0
        @children.each {|child| child.send(:append_rows_to, table, stack)}
      else
        table << stack.flatten(1)
      end
      stack.pop if @content
    end
  end
end
