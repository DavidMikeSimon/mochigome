require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

describe Ernie::Query do
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

  it "returns an empty DataNode if no focus objects given" do
    q = Ernie::Query.new([Category, Product])
    data_node = q.focused_on([])
    assert_empty data_node
    assert_empty data_node.children
  end

  it "can build a one-layer DataNode" do
    q = Ernie::Query.new([Product])
    data_node = q.focused_on(@product_a)
    assert_equal [@product_a], data_node.children.map{|c| c[:obj]}
    assert_empty data_node.children[0].children
  end

  it "can build a two-layer DataNode focused on a record with a belongs_to association" do
    q = Ernie::Query.new([Category, Product])
    data_node = q.focused_on(@product_a)
    assert_equal [@category1], data_node.children.map{|c| c[:obj]}
    assert_equal [@product_a], data_node.children[0].children.map{|c| c[:obj]}
    assert_empty data_node.children[0].children[0].children
  end

  it "can build a two-layer DataNode focused on an array of records in the second layer" do
    q = Ernie::Query.new([Category, Product])
    data_node = q.focused_on([@product_a, @product_d, @product_b])
    assert_equal [@category1, @category2], data_node.children.map{|c| c[:obj]}
    assert_equal [@product_a, @product_b], data_node.children[0].children.map{|c| c[:obj]}
    assert_equal [@product_d], data_node.children[1].children.map{|c| c[:obj]}
  end

  it "can build a two-layer DataNode focused on a record with a has_many association" do
    q = Ernie::Query.new([Category, Product])
    data_node = q.focused_on(@category1)
    assert_equal [@category1], data_node.children.map{|c| c[:obj]}
    assert_equal [@product_a, @product_b], data_node.children[0].children.map{|c| c[:obj]}
    assert_empty data_node.children[0].children[0].children
  end
end
