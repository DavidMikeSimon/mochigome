require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

describe Ernie::DataNode do
  before do
    @category1 = create(:category, :name => "Category 1")
    @product_a = create(:product, :name => "Product A", :category => @category1)
    @product_b = create(:product, :name => "Product B", :category => @category1)
    @category2 = create(:category, :name => "Category 2")
    @product_c = create(:product, :name => "Product C", :category => @category2)
    @product_d = create(:product, :name => "Product D", :category => @category2)
    @boring_datum = create(:boring_datum)
    @store1 = create(:store, :name => "Store 1")
    @store2 = create(:store, :name => "Store 2")
    @sp1a = create(:store_product, :product => @product_a, :store => @store1)
    @sp1b = create(:store_product, :product => @product_b, :store => @store1)
    @sp1d = create(:store_product, :product => @product_d, :store => @store1)
    @sp2a = create(:store_product, :product => @product_a, :store => @store2)
    @sp2c = create(:store_product, :product => @product_c, :store => @store2)
    3.times { create(:sale, :store_product => @sp1a) }
    2.times { create(:sale, :store_product => @sp1b) }
    4.times { create(:sale, :store_product => @sp1d) }
    5.times { create(:sale, :store_product => @sp2a) }
    3.times { create(:sale, :store_product => @sp2c) }
  end

  describe "when just created" do
    before do
      @datanode = Ernie::DataNode.new([Category, Product])
    end

    it "knows what its layer_types are" do
      assert_equal [Category, Product], @datanode.layer_types
    end

    it "is empty by default" do
      assert_equal 0, @datanode.size
    end

    it "can have items added to the top layer" do
      @datanode << @category1
      @datanode << @category2
      assert_equal 2, @datanode.size
      assert_equal @category1, @datanode.first.content
    end

    it "can have items added at multiple layers" do
      @datanode << @category1
      @datanode.first << @category1.products
      assert_equal 1, @datanode.size
      assert_equal 2, @datanode.first.size
      assert_equal @product_a, @datanode.first.first.content
      assert_equal Product, @datanode.first.layer_types.first
    end

    it "can have items already in DataNodes added" do
      @datanode << Ernie::DataNode.new([Product], @category1)
      @datanode.first << @category1.products.map{|prod| Ernie::DataNode.new([], prod)}
      assert_equal 1, @datanode.size
      assert_equal 2, @datanode.first.size
      assert_equal @product_a, @datanode.first.first.content
      assert_equal Product, @datanode.first.layer_types.first
    end

    it "supports looking up children by content or index" do
      @datanode << [@category1, @category2]
      @datanode[@category1] << @product_a
      @datanode[@category2] << @product_c
      assert_equal @product_a, @datanode[0].first.content
      assert_equal @product_c, @datanode[1].first.content
    end

    it "doesn't accept items of the wrong type for the layer" do
      assert_raises Ernie::LayerMismatchError do
        @datanode << @product1
      end
      @datanode << @category1
      assert_raises Ernie::LayerMismatchError do
        @datanode.first << @category2
      end
    end

    it "won't search for an item of the wrong type on a layer" do
      assert_raises Ernie::LayerMismatchError do
        @datanode[@product_d] # Should be a Category, not a Product
      end
    end

    it "won't search for nonsense" do
      assert_raises ArgumentError do
        @datanode["foobar"]
      end
    end

    it "returns the new child DataNode(s) from a concatenation" do
      new_child = @datanode << @category1
      assert_equal @datanode[0], new_child

      new_children = @datanode[0] << [@product_a, @product_b]
      assert_equal @datanode[0].children, new_children
    end
  end

  describe "when populated" do
    before do
      @datanode = Ernie::DataNode.new([Category, Product])
      @datanode << [@category1, @category2]
      @datanode[@category1] << @category1.products.all(:order => :id)
      @datanode[@category2] << @category2.products.all(:order => :id)
    end

    it "can return field and aggregate data for its content" do
      fields = @datanode[@category1][@product_a].content_fields
      assert_includes fields, {:name => "name", :value => "Product A"}
      assert_includes fields, {:name => "price", :value => 19.95}
      assert_includes fields, {:name => "sales_count", :value => 8}
    end

    it "can return an array of childrens' ActiveRecords" do
      assert_equal [@category1, @category2], @datanode.children_content
      assert_equal @category1.products, @datanode[@category1].children_content
    end

    it "can convert to an XML document" do
      doc = Nokogiri::XML(@datanode.to_xml.to_s)
      category_nodes = doc.xpath('//data/category')
      assert_equal @category1.id.to_s, category_nodes[0]['recId']
      assert_equal @category2.id.to_s, category_nodes[1]['recId']
      assert_equal @category2.name, category_nodes[1].xpath('.//name').first.content
      assert_equal "19.95", category_nodes[1].xpath('.//productsAveragePrice').first.content
      product_nodes = category_nodes[1].xpath('.//product')
      assert_equal @product_c.id.to_s, product_nodes[0]['recId']
      assert_equal @product_d.id.to_s, product_nodes[1]['recId']
      assert_equal @product_c.name, product_nodes[0].xpath('.//name').first.content
      assert_equal @product_c.price.to_s, product_nodes[0].xpath('.//price').first.content
      assert_equal "3", product_nodes[0].xpath('.//salesCount').first.content
      assert_equal "4", product_nodes[1].xpath('.//salesCount').first.content
    end

    it "can convert to a Ruport table" do
      table = @datanode.to_ruport_table
      titles = [
        "Category::name",
        "Category::products_average_price",
        "Product::name",
        "Product::price",
        "Product::sales_count"
      ]
      assert_equal titles, table.column_names
      values = [@category2.name, 19.95, @product_c.name, @product_c.price, 3]
      assert_equal values, table.data[2].to_a
    end
  end
end
