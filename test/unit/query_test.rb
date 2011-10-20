require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

describe Mochigome::Query do
  before do
    @category1 = create(:category, :name => "Category 1")
    @product_a = create(:product, :name => "Product A", :category => @category1)
    @product_b = create(:product, :name => "Product B", :category => @category1)

    # Belongs to a category, but fails Category's has_many(:products) conditions
    @product_x = create(:product, :name => "Product X", :category => @category1, :categorized => false)
    
    @category2 = create(:category, :name => "Category 2")
    @product_c = create(:product, :name => "Product C", :category => @category2)
    @product_d = create(:product, :name => "Product D", :category => @category2)
    
    @product_e = create(:product, :name => "Product E") # No category

    @john = create(:owner, :first_name => "John", :last_name => "Smith")
    @store_x = create(:store, :name => "John's Store", :owner => @john)

    @jane = create(:owner, :first_name => "Jane", :last_name => "Doe")
    @store_y = create(:store, :name => "Jane's Store (North)", :owner => @jane)
    @store_z = create(:store, :name => "Jane's Store (South)", :owner => @jane)

    @sp_xa = create(:store_product, :store => @store_x, :product => @product_a)
    @sp_xc = create(:store_product, :store => @store_x, :product => @product_c)
    @sp_ya = create(:store_product, :store => @store_y, :product => @product_a)
    @sp_yb = create(:store_product, :store => @store_y, :product => @product_b)
    @sp_ye = create(:store_product, :store => @store_y, :product => @product_e)
    @sp_zc = create(:store_product, :store => @store_z, :product => @product_c)
    @sp_zd = create(:store_product, :store => @store_z, :product => @product_d)

    [
      [@sp_xa, 5],
      [@sp_xc, 3],
      [@sp_ya, 4],
      [@sp_yb, 6],
      [@sp_ye, 1],
      [@sp_zc, 2],
      [@sp_zd, 3]
    ].each do |sp, n|
      n.times{create(:sale, :store_product => sp)}
    end
  end

  # Convenience function to check DataSet output validity
  def assert_equal_objs(a, b)
    assert_equal a.size, b.size
    # Not checking aggregate data because we don't know abut a's context here
    a.zip(b).each do |obj, fields|
      obj.mochigome_focus.field_data.each do |k,v|
        assert_equal v, fields[k]
      end
    end
  end

  it "returns an empty DataNode if no objects given" do
    q = Mochigome::Query.new([Category, Product])
    data_node = q.run([])
    assert_empty data_node
    assert_empty data_node.children
  end

  it "can build a one-layer DataNode" do
    q = Mochigome::Query.new([Product])
    data_node = q.run(@product_a)
    assert_equal_objs [@product_a], data_node.children
    assert_empty data_node.children[0].children
  end

  it "uses the model focus's group name for the DataNode's type name" do
    q = Mochigome::Query.new([Store])
    data_node = q.run(@store_x)
    assert_equal "Storefront", data_node.children[0].name.to_s
  end

  it "can build a two-layer tree from a record with a belongs_to association" do
    q = Mochigome::Query.new([Category, Product])
    data_node = q.run(@product_a)
    assert_equal_objs [@category1], data_node.children
    assert_equal_objs [@product_a], data_node.children[0].children
    assert_empty data_node.children[0].children[0].children
  end

  it "can build a two-layer tree from an array of records in the second layer" do
    q = Mochigome::Query.new([Category, Product])
    data_node = q.run([@product_a, @product_d, @product_b])
    assert_equal_objs [@category1, @category2], data_node.children
    assert_equal_objs [@product_a, @product_b], data_node.children[0].children
    assert_equal_objs [@product_d], data_node.children[1].children
  end

  it "can build a two-layer tree from a record with a has_many association" do
    q = Mochigome::Query.new([Category, Product])
    data_node = q.run(@category1)
    assert_equal_objs [@category1], data_node.children
    assert_equal_objs [@product_a, @product_b], data_node.children[0].children
    assert_empty data_node.children[0].children[0].children
  end

  it "cannot build a DataNode tree when given disconnected layers" do
    q = Mochigome::Query.new([Category, BoringDatum])
    assert_raises Mochigome::QueryError do
      data_node = q.run(@category1)
    end
  end

  it "can build a three-layer tree from any layer" do
    q = Mochigome::Query.new([Owner, Store, Product])
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

  it "collects aggregate data in the context of all layers when traversing down" do
    q = Mochigome::Query.new([Owner, Store, Product])
    data_node = q.run([@john, @jane])
    # Store X, Product C
    assert_equal "Product C", data_node.children[0].children[0].children[1]['name']
    assert_equal 3, data_node.children[0].children[0].children[1]['Sales count']
    # Store Z, Product C
    assert_equal "Product C", data_node.children[1].children[1].children[0]['name']
    assert_equal 2, data_node.children[1].children[1].children[0]['Sales count']
  end

  it "collects aggregate data in the context of all layers when traversing up" do
    q = Mochigome::Query.new([Owner, Store, Product])
    data_node = q.run(@product_c)
    # Store X, Product C
    assert_equal "Product C", data_node.children[0].children[0].children[0]['name']
    assert_equal 3, data_node.children[0].children[0].children[0]['Sales count']
    # Store Z, Product C
    assert_equal "Product C", data_node.children[1].children[0].children[0]['name']
    assert_equal 2, data_node.children[1].children[0].children[0]['Sales count']
  end

  it "collects aggregate data in the context of distant layers" do
    # TODO: Implement me! I think this is necessary to justify focus_data_node_objs passing obj_stack
  end

  it "puts a comment on the root node describing the query" do
    q = Mochigome::Query.new([Owner, Store, Product])
    data_node = q.run([@store_x, @store_y, @store_z])
    c = data_node.comment
    assert_match c, /^Mochigome Version: #{Mochigome::VERSION}\n/
    assert_match c, /\nTime: \w{3} \w{3} \d+ .+\n/
    assert_match c, /\nLayers: Owner => Store => Product\n/
    assert_match c, /\nAR Association Path:\n\* <- Owner.+\n\* == Store.+\n\* -> Product.+\n/
  end

  it "puts a descriptive comment on the first node of each layer" do
    q = Mochigome::Query.new([Owner, Store, Product])
    data_node = q.run([@store_x, @store_y, @store_z])

    owner_comment = data_node.children[0].comment
    assert owner_comment
    assert_nil data_node.children[1].comment # No comment on second owner

    store_comment = data_node.children[0].children[0].comment
    assert store_comment
    assert_nil data_node.children[1].children[0].comment # No comment on second store

    product_comment = data_node.children[0].children[0].children[0].comment
    assert product_comment
    assert_nil data_node.children[0].children[0].children[1].comment # No comment on 2nd product

    [owner_comment, store_comment, product_comment].each do |comment|
      assert_match comment, /^Context:\nOwner:#{@john.id}.*\n/ # Owner is always in context
    end
  end
end
