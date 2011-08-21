require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

describe Ernie::Aggregator do
  before do
    @category1 = create(:category, :name => "Category 1")
    @product_a = create(:product, :name => "Product A", :category => @category1)
    @product_b = create(:product, :name => "Product B", :category => @category1)
    
    @category2 = create(:category, :name => "Category 2")
    @product_c = create(:product, :name => "Product C", :category => @category2)
    @product_d = create(:product, :name => "Product D", :category => @category2)
    
    @product_e = create(:product, :name => "Product E") # No category

    @john = create(:owner, :first_name => "John", :last_name => "Smith")
    @store_x = create(:store, :name => "John's Store", :owner => @john)

    @jane = create(:owner, :first_name => "Jane", :last_name => "Doe")
    @store_y = create(:store, :name => "Jane's Store (North)", :owner => @jane)
    @store_z = create(:store, :name => "Jane's Store (South)", :owner => @jane)

    @store_x.products << @product_a
    @store_x.products << @product_c
    @store_y.products << @product_a
    @store_y.products << @product_b
    @store_y.products << @product_e
    @store_z.products << @product_c
    @store_z.products << @product_d
  end

  it "can build a one-layer DataSet" do
    agg = Ernie::Aggregator.new([Product])
    data_set = agg.focused_on(@product_a)
    assert_equal [@product_a], data_set.children_content
    assert_equal [], data_set[@product_a].children_content
  end

  it "can build a two-layer DataSet focused on a record with a belongs_to association" do
    agg = Ernie::Aggregator.new([Category, Product])
    data_set = agg.focused_on(@product_a)
    assert_equal [@category1], data_set.children_content
    assert_equal [@product_a], data_set[@category1].children_content
    assert_equal [], data_set[@category1][@product_a].children_content
  end
end
