# Module for creating and exporting strata-classed trees of ActiveRecords

module Ernie
  class DataSet
    def initialize(dataset_name, &block)
      @dataset_name = dataset_name.to_s
      @root_node = Node.new()
      @root_node.instance_eval(&block) 
    end

    def to_xml
      xml = Builder::XmlMarkup.new
      xml.tag!((@dataset_name + "_data_set").camelize(:lower)) do
        @root_node.append_xml_to(xml)
      end
    end

    def to_ruport_table
      table = Ruport::Data::Table.new(:column_names => @root_node.flat_column_names)
      @root_node.append_rows_to(table)
      table
    end

    private

    class Node
      attr_reader :content

      def initialize(content = nil)
        @content = content
        @children = []
      end

      def layer(items, options = {}, &block)
        content_func = options[:content] ||= lambda{|x| x}
        passthru_func = options[:passthru] # Could be nil
        items.each do |item|
          child_content = content_func.call(item)
          child = Node.new(child_content)
          @children << child
          if block
            args = [child_content]
            args << passthru_func.call(item) if passthru_func
            child.instance_exec(*args, &block)
          end
        end
      end

      def append_xml_to(x)
        if content
          x.tag!(content.ernie_tag_name.camelize(:lower), {:id => content.id}) do
            content.ernie_field_data.each do |field|
              x.tag!(field[:name].camelize(:lower), field[:value])
            end
            @children.each {|child| child.append_xml_to(x)}
          end
        else
          @children.each {|child| child.append_xml_to(x)}
        end
      end

      def flat_column_names
        if @content
          prefix_tag = @content.ernie_tag_name
          colnames = @content.class.ernie_field_list.map{|f| "#{prefix_tag}::#{f[:name]}"}
        else
          colnames = []
        end
        if @children.size > 0
          colnames += @children.first.flat_column_names
        end
        colnames
      end

      def append_rows_to(table, stack = [])
        stack.push @content.ernie_field_data.map{|r| r[:value]} if @content
        if @children.size > 0
          @children.each {|child| child.append_rows_to(table, stack)}
        else
          table << stack.flatten(1)
        end
        stack.pop if @content
      end
    end
  end
end
