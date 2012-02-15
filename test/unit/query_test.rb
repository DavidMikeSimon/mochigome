require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

describe Mochigome::Query do
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

  # Convenience functions to check DataNode output validity

  def assert_equal_children(a, node)
    b = node.children
    assert_equal a.size, b.size
    # Not checking aggregate data because we don't know about a's context here
    a.zip(b).each do |obj, fields|
      obj.mochigome_focus.field_data.each do |k,v|
        assert_equal v, fields[k]
      end
    end
  end

  def assert_no_children(obj)
    assert_empty obj.children
  end

  it "returns an empty DataNode if no objects given" do
    q = Mochigome::Query.new([Category, Product])
    data_node = q.run([])
    assert_empty data_node
    assert_no_children data_node
  end

  it "can build a one-layer DataNode" do
    q = Mochigome::Query.new([Product])
    data_node = q.run(@product_a)
    assert_equal_children [@product_a], data_node
    assert_no_children data_node/0
  end

  it "uses the model focus's type name for the DataNode's type name" do
    q = Mochigome::Query.new([Store])
    data_node = q.run(@store_x)
    assert_equal "Storefront", (data_node/0).type_name.to_s
  end

  it "adds an internal_type attribute containing the model class's name" do
    q = Mochigome::Query.new([Store])
    data_node = q.run(@store_x)
    assert_equal "Store", (data_node/0)[:internal_type]
  end

  it "can build a two-layer tree from a record with a belongs_to association" do
    q = Mochigome::Query.new([Category, Product])
    data_node = q.run(@product_a)
    assert_equal_children [@category1], data_node
    assert_equal_children [@product_a], data_node/0
    assert_no_children data_node/0/0
  end

  it "can build a two-layer tree from an array of records in the second layer" do
    q = Mochigome::Query.new([Category, Product])
    data_node = q.run([@product_a, @product_d, @product_b])
    assert_equal_children [@category1, @category2], data_node
    assert_equal_children [@product_a, @product_b], data_node/0
    assert_equal_children [@product_d], data_node/1
  end

  it "can build a two-layer tree from a record with a has_many association" do
    q = Mochigome::Query.new([Category, Product])
    data_node = q.run(@category1)
    assert_equal_children [@category1], data_node
    assert_equal_children [@product_a, @product_b], data_node/0
    assert_no_children data_node/0/0
  end

  it "cannot build a Query through disconnected layers" do
    assert_raises Mochigome::QueryError do
      q = Mochigome::Query.new([Category, BoringDatum])
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
      assert_equal_children [@john, @jane], data_node
      assert_equal_children [@store_x], data_node/0
      assert_equal_children [@store_y, @store_z], data_node/1
      assert_equal_children [@product_a, @product_c], data_node/0/0
      assert_equal_children [@product_c, @product_d], data_node/1/1
    end
  end

  it "collects aggregate data in the context of all layers when traversing down" do
    q = Mochigome::Query.new([Owner, Store, Product])
    data_node = q.run([@john, @jane])
    # Store X, Product C
    assert_equal "Product C", (data_node/0/0/1).name
    assert_equal 3, (data_node/0/0/1)['Sales count']
    # Store Z, Product C
    assert_equal "Product C", (data_node/1/1/0).name
    assert_equal 2, (data_node/1/1/0)['Sales count']
  end

  it "collects aggregate data in the context of all layers when traversing up" do
    q = Mochigome::Query.new([Owner, Store, Product])
    data_node = q.run(@product_c)
    # Store X, Product C
    assert_equal "Product C", (data_node/0/0/0).name
    assert_equal 3, (data_node/0/0/0)['Sales count']
    # Store Z, Product C
    assert_equal "Product C", (data_node/1/0/0).name
    assert_equal 2, (data_node/1/0/0)['Sales count']
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
    assert_match c, /\nAR Path: Owner => Store => StoreProduct => Product\n/
  end

  it "puts a descriptive comment on the first node of each layer" do
    q = Mochigome::Query.new([Owner, Store, Product])
    data_node = q.run([@store_x, @store_y, @store_z])

    owner_comment = (data_node/0).comment
    assert owner_comment
    assert_nil (data_node/1).comment # No comment on second owner

    store_comment = (data_node/0/0).comment
    assert store_comment
    assert_nil (data_node/1/0).comment # No comment on second store

    product_comment = (data_node/0/0/0).comment
    assert product_comment
    assert_nil (data_node/0/0/1).comment # No comment on 2nd product

    [owner_comment, store_comment, product_comment].each do |comment|
      assert_match comment, /^Context:\nOwner:#{@john.id}.*\n/ # Owner is always in context
    end
  end

  it "will not allow a query on targets of different types" do
    q = Mochigome::Query.new([Owner, Store, Product])
    assert_raises Mochigome::QueryError do
      q.run([@store_x, @john])
    end
  end

  it "will not allow a query on targets not in the layer list" do
    q = Mochigome::Query.new([Product])
    assert_raises Mochigome::QueryError do
      q.run(@category1)
    end
  end
end
