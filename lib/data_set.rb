module Ernie
  class DataSet
    include Enumerable

    attr_reader :content
    attr_reader :layers

    def initialize(layers, content = nil)
      layers.each do |cls|
        unless cls.acts_as_report_focus?
          raise Ernie::InvalidLayerError.new(
            "Class #{cls.name} cannot be a DataSet layer since it does not act as a report focus"
          )
        end
      end

      @layers = layers
      @content = content
      @children = []
    end
    delegate :each, :size, :to => :@children

    def <<(item)
      unless item.is_a?(layers.first)
        raise LayerMismatchError.new "Need a #{layers.first.name} but got a #{item.class.name}"
      end
      @children << DataSet.new(layers.drop(1), item)
    end

    def concat(items)
      items.each {|i| self << i}
    end

    def to_xml
      xml = Builder::XmlMarkup.new
      xml.tag! "dataSet" do
        append_xml_to(xml)
      end
    end

    def to_ruport_table
      table = Ruport::Data::Table.new(:column_names => @root_node.flat_column_names)
      append_rows_to(table)
      table
    end

    private

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
