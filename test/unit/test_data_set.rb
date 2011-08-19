require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

class TestDataSet < Test::Unit::TestCase
  setup do
    @category1 = create(:category, :name => "Category 1")
    @product_a = create(:product, :name => "Product A", :category => @category1)
    @product_b = create(:product, :name => "Product B", :category => @category1)
    @category2 = create(:category, :name => "Category 2")
    @product_c = create(:product, :name => "Product C", :category => @category2)
    @product_d = create(:product, :name => "Product D", :category => @category2)
    @boring_datum = create(:boring_datum)
  end

  context "a new DataSet" do
    setup do
      @dataset = Ernie::DataSet.new([Category, Product])
    end

    should "know what its layers are" do
      assert_equal [Category, Product], @dataset.layers
    end

    should "be empty by default" do
      assert_equal 0, @dataset.size
    end

    could "have items added to the top layer" do
      @dataset << @category1
      @dataset << @category2
      assert_equal 2, @dataset.size
      assert_equal @category1, @dataset.first.content
    end

    could "have items added at multiple layers" do
      @dataset << @category1
      @dataset.first.concat  @category1.products 
      assert_equal 1, @dataset.size
      assert_equal 2, @dataset.first.size
      assert_equal @product_a, @dataset.first.first.content
      assert_equal Product, @dataset.first.layers.first
    end

    should "support looking up children by content or index" do
      @dataset.concat [@category1, @category2]
      @dataset[@category1] << @product_a
      @dataset[@category2] << @product_c
      assert_equal @product_a, @dataset[0].first.content
      assert_equal @product_c, @dataset[1].first.content
    end

    should "not accept items of the wrong type for the layer" do
      assert_raise Ernie::LayerMismatchError do
        @dataset << @product1
      end
      @dataset << @category1
      assert_raise Ernie::LayerMismatchError do
        @dataset.first << @category2
      end
    end

    should "not search for an item of the wrong type on a layer" do
      assert_raise Ernie::LayerMismatchError do
        @dataset[@product_d] # Should be a Category, not a Product
      end
    end

    should "prohibit searching for nonsense" do
      assert_raise ArgumentError do
        @dataset["foobar"]
      end
    end

    should "only accept layers that act as report focus" do
      assert_raise Ernie::InvalidLayerError do
        Ernie::DataSet.new([Category, BoringDatum])
      end
    end

    should "return the new child DataSet(s) from a concatenation" do
      child = @dataset << @category1
      assert_equal @dataset[0], child

      children = @dataset[0].concat [@product_a, @product_b]
      assert_equal @dataset[0].to_a, children
    end
  end

  context "a populated DataSet" do
    setup do
      @dataset = Ernie::DataSet.new([Category, Product])
      @dataset.concat [@category1, @category2]
      @dataset[@category1].concat @category1.products
      @dataset[@category2].concat @category2.products
    end

    could "convert to an XML document" do
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
  end
end
