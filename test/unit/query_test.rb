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

  # Convenience functions
  def get_objs(array)
    array.map{|c| c[:obj]}
  end

  def assert_equal_objs(a, b)
    assert_equal a, get_objs(b)
  end

  it "returns an empty DataNode if no objects given" do
    q = Ernie::Query.new([Category, Product])
    data_node = q.run([])
    assert_empty data_node
    assert_empty data_node.children
  end

  it "can build a one-layer DataNode" do
    q = Ernie::Query.new([Product])
    data_node = q.run(@product_a)
    assert_equal_objs [@product_a], data_node.children
    assert_empty data_node.children[0].children
  end

  it "can build a two-layer DataNode from a record with a belongs_to association" do
    q = Ernie::Query.new([Category, Product])
    data_node = q.run(@product_a)
    assert_equal_objs [@category1], data_node.children
    assert_equal_objs [@product_a], data_node.children[0].children
    assert_empty data_node.children[0].children[0].children
  end

  it "can build a two-layer DataNode from an array of records in the second layer" do
    q = Ernie::Query.new([Category, Product])
    data_node = q.run([@product_a, @product_d, @product_b])
    assert_equal_objs [@category1, @category2], data_node.children
    assert_equal_objs [@product_a, @product_b], data_node.children[0].children
    assert_equal_objs [@product_d], data_node.children[1].children
  end

  it "can build a two-layer DataNode from a record with a has_many association" do
    q = Ernie::Query.new([Category, Product])
    data_node = q.run(@category1)
    assert_equal_objs [@category1], data_node.children
    assert_equal_objs [@product_a, @product_b], data_node.children[0].children
    assert_empty data_node.children[0].children[0].children
  end

  it "can build a three-layer DataNode from any layer" do
    q = Ernie::Query.new([Owner, Store, Product])
    [
      [@john, @jane],
      [@store_x, @store_y, @store_z],
      [@product_a, @product_b, @product_c, @product_d, @product_e]
    ].each do |tgt|
      data_node = q.run(tgt)
      assert_equal_objs [@john, @jane], data_node.children
      assert_equal_objs [@store_x], data_node.children[0].children
      assert_equal_objs [@store_y, @store_z], data_node.children[1].children
      assert_equal_objs [@product_a, @product_c],
        data_node.children[0].children[0].children
      assert_equal_objs [@product_c, @product_d],
        data_node.children[1].children[1].children
    end
  end
end
