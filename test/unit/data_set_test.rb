require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

describe Ernie::DataSet do
  before do
    @category1 = create(:category, :name => "Category 1")
    @product_a = create(:product, :name => "Product A", :category => @category1)
    @product_b = create(:product, :name => "Product B", :category => @category1)
    @category2 = create(:category, :name => "Category 2")
    @product_c = create(:product, :name => "Product C", :category => @category2)
    @product_d = create(:product, :name => "Product D", :category => @category2)
    @boring_datum = create(:boring_datum)
  end

  describe "when just created" do
    before do
      @dataset = Ernie::DataSet.new([Category, Product])
    end

    it "knows what its layer_types are" do
      assert_equal [Category, Product], @dataset.layer_types
    end

    it "is empty by default" do
      assert_equal 0, @dataset.size
    end

    it "can have items added to the top layer" do
      @dataset << @category1
      @dataset << @category2
      assert_equal 2, @dataset.size
      assert_equal @category1, @dataset.first.content
    end

    it "can have items added at multiple layers" do
      @dataset << @category1
      @dataset.first << @category1.products
      assert_equal 1, @dataset.size
      assert_equal 2, @dataset.first.size
      assert_equal @product_a, @dataset.first.first.content
      assert_equal Product, @dataset.first.layer_types.first
    end

    it "can have items already in DataSets added" do
      @dataset << Ernie::DataSet.new([Product], @category1)
      @dataset.first << @category1.products.map{|prod| Ernie::DataSet.new([], prod)}
      assert_equal 1, @dataset.size
      assert_equal 2, @dataset.first.size
      assert_equal @product_a, @dataset.first.first.content
      assert_equal Product, @dataset.first.layer_types.first
    end

    it "supports looking up children by content or index" do
      @dataset << [@category1, @category2]
      @dataset[@category1] << @product_a
      @dataset[@category2] << @product_c
      assert_equal @product_a, @dataset[0].first.content
      assert_equal @product_c, @dataset[1].first.content
    end

    it "doesn't accept items of the wrong type for the layer" do
      assert_raises Ernie::LayerMismatchError do
        @dataset << @product1
      end
      @dataset << @category1
      assert_raises Ernie::LayerMismatchError do
        @dataset.first << @category2
      end
    end

    it "won't search for an item of the wrong type on a layer" do
      assert_raises Ernie::LayerMismatchError do
        @dataset[@product_d] # Should be a Category, not a Product
      end
    end

    it "won't search for nonsense" do
      assert_raises ArgumentError do
        @dataset["foobar"]
      end
    end

    it "returns the new child DataSet(s) from a concatenation" do
      new_child = @dataset << @category1
      assert_equal @dataset[0], new_child

      new_children = @dataset[0] << [@product_a, @product_b]
      assert_equal @dataset[0].children, new_children
    end
  end

  describe "when populated" do
    before do
      @dataset = Ernie::DataSet.new([Category, Product])
      @dataset << [@category1, @category2]
      @dataset[@category1] << @category1.products
      @dataset[@category2] << @category2.products
    end

    it "can be shallowly cloned, returning a new DataSet with the same children" do
      evil_twin = @dataset[@category1].clone
      refute_equal evil_twin.object_id, @dataset[@category1].object_id
      assert_equal evil_twin.children, @dataset[@category1].children
      evil_twin << @product_d
      assert_includes @dataset[@category1].children_content, @product_d
    end

    it "returns an array of childrens' ActiveRecords with children_content" do
      assert_equal [@category1, @category2], @dataset.children_content
      assert_equal @category1.products, @dataset[@category1].children_content
    end

    it "can convert to an XML document" do
      doc = Nokogiri::XML(@dataset.to_xml.to_s)
      category_nodes = doc.xpath('//dataSet/category')
      assert_equal @category1.id.to_s, category_nodes[0]['recId']
      assert_equal @category2.id.to_s, category_nodes[1]['recId']
      assert_equal @category2.name, category_nodes[1].xpath('.//name').first.content
      product_nodes = category_nodes[1].xpath('.//product')
      assert_equal @product_c.id.to_s, product_nodes[0]['recId']
      assert_equal @product_d.id.to_s, product_nodes[1]['recId']
      assert_equal @product_c.name, product_nodes[0].xpath('.//name').first.content
      assert_equal @product_c.price.to_s, product_nodes[0].xpath('.//price').first.content
    end

    it "can convert to a Ruport table" do
      table = @dataset.to_ruport_table
      titles = ["Category::name", "Product::name", "Product::price"]
      assert_equal titles, table.column_names
      values = [@category1.name, @product_b.name, @product_b.price]
      assert_equal values, table.data[1].to_a
    end
  end
end
