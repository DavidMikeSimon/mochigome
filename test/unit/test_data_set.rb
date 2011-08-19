require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

class TestDataSet < Test::Unit::TestCase
  context "a DataSet" do
    setup do
      @dataset = Ernie::DataSet.new([Category, Product])

      @category1 = create(:category, :name => "Category 1")
      @product_a = create(:product, :name => "Product A", :category => @category1)
      @product_b = create(:product, :name => "Product B", :category => @category1)
      @category2 = create(:category, :name => "Category 2")
      @product_c = create(:product, :name => "Product C", :category => @category2)
      @product_d = create(:product, :name => "Product D", :category => @category2)
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

    should "not accept items of the wrong type for the layer" do
      assert_raise Ernie::LayerMismatchError do
        @dataset << @product1
      end
      @dataset << @category1
      assert_raise Ernie::LayerMismatchError do
        @dataset.first << @category2
      end
    end
  end
end
