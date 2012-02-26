require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

describe Mochigome::Query do
  before do
    @category1 = create(:category, :name => "Category 1")
    @product_a = create(:product, :name => "Product A", :category => @category1, :price => 5)
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

  after do
    Category.delete_all
    Product.delete_all
    Owner.delete_all
    Store.delete_all
    StoreProduct.delete_all
    Sale.delete_all
  end

  # Convenience functions to check DataNode output validity

  def assert_equal_children(a, node)
    b = node.children
    assert_equal a.size, b.size
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

  it "orders by ID by default" do
    q = Mochigome::Query.new([Product])
    data_node = q.run([@product_b, @product_a, @product_c])
    assert_equal_children [@product_a, @product_b, @product_c], data_node
  end

  it "orders by custom fields when the model focus settings specify so" do
    q = Mochigome::Query.new([Category])
    catZ = create(:category, :name => "Zebras") # Created first, has lower ID
    catA = create(:category, :name => "Apples")
    data_node = q.run([catZ, catA])
    assert_equal catA.name, (data_node/0).name
    assert_equal catZ.name, (data_node/1).name
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

  it "collects aggregate data by grouping on all layers" do
    q = Mochigome::Query.new(
      [Owner, Store, Product],
      :aggregate_sources => [[Product, Sale]]
    )

    data_node = q.run([@john, @jane])
    # Store X, Product C
    assert_equal "Product C", (data_node/0/0/1).name
    assert_equal 3, (data_node/0/0/1)['Sales count']
    # Store Z, Product C
    assert_equal "Product C", (data_node/1/1/0).name
    assert_equal 2, (data_node/1/1/0)['Sales count']

    data_node = q.run(@product_c)
    # Store X, Product C
    assert_equal "Product C", (data_node/0/0/0).name
    assert_equal 3, (data_node/0/0/0)['Sales count']
    # Store Z, Product C
    assert_equal "Product C", (data_node/1/0/0).name
    assert_equal 2, (data_node/1/0/0)['Sales count']
  end

  it "collects aggregate data on layers above the focus" do
    q = Mochigome::Query.new(
      [Owner, Store, Product],
      :aggregate_sources => [[Product, Sale]]
    )

    data_node = q.run([@john, @jane])

    assert_equal "Jane's Store (North)", (data_node/1/0).name
    assert_equal 11, (data_node/1/0)['Sales count']

    assert_equal "Jane Doe", (data_node/1).name
    assert_equal 16, (data_node/1)['Sales count']

    assert_equal 24, data_node['Sales count']
  end

  it "can do conditional counts" do
    q = Mochigome::Query.new(
      [Category],
      :aggregate_sources => [[Category, Product]]
    )
    data_node = q.run([@category1, @category2])
    assert_equal 1, (data_node/0)['Expensive products']
    assert_equal 2, (data_node/1)['Expensive products']
  end

  # TODO: Test against double-counting data rows in aggregations
  # TODO: Test case where data model is already in layer path
  # TODO: Test case where the condition is deeper than the focus model
  # TODO: Test some of the other predicate functions
  # TODO: Test that we actually go through the focus, to avoid i.e. the JSAS
  # bug where we were summing School->AR instead of School->Section->Student->AR

  it "puts a comment on the root node describing the query" do
    q = Mochigome::Query.new([Owner, Store, Product])
    data_node = q.run([@store_x, @store_y, @store_z])
    c = data_node.comment
    assert_match c, /^Mochigome Version: #{Mochigome::VERSION}\n/
    assert_match c, /\nReport Generated: \w{3} \w{3} \d+ .+\n/
    assert_match c, /\nLayers: Owner => Store => Product\n/
    assert_match c, /\nAR Path: Owner => Store => StoreProduct => Product\n/
  end

  it "names the root node 'report' by default" do
    q = Mochigome::Query.new([Owner, Store, Product])
    data_node = q.run([@store_x, @store_y, @store_z])
    assert_equal "report", data_node.name
  end

  it "can set the root node's name to a provided value" do
    q = Mochigome::Query.new(
      [Owner, Store, Product],
      :root_name => "cheese"
    )
    data_node = q.run([@store_x, @store_y, @store_z])
    assert_equal "cheese", data_node.name
  end

  it "will complain if initialized with an unknown option" do
    assert_raises Mochigome::QueryError do
      q = Mochigome::Query.new([Owner, Store, Product], :flim_flam => 123)
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

  it "can use a provided access filter function to limit query results" do
    af = proc do |cls|
      return {} unless cls == Product
      return {
        :condition => Arel::Table.new(Product.table_name)[:category_id].gt(0)
      }
    end
    q = Mochigome::Query.new([Product], :access_filter => af)
    dn = q.run(Product.all) # FIXME: Need a better way of doing "all objs" queries
    assert_equal 4, dn.children.size
    refute dn.children.any?{|c| c.name == "Product E"}
  end

  it "can do joins at the request of an access filter" do
    af = proc do |cls|
      return {} unless cls == Product
      return {
        :join_models => [Store],
        :condition => Arel::Table.new(Store.table_name)[:name].matches("Jo%")
      }
    end
    q = Mochigome::Query.new([Product], :access_filter => af)
    dn = q.run(Product.all) # FIXME: Need a better way of doing "all objs" queries
    assert_equal 2, dn.children.size
    refute dn.children.any?{|c| c.name == "Product E"}
  end

  it "access filter joins will not duplicate joins already in the query" do
    af = proc do |cls|
      return {} unless cls == Product
      return {
        :join_models => [Store],
        :condition => Arel::Table.new(Store.table_name)[:name].matches("Jo%")
      }
    end
    q = Mochigome::Query.new([Product, Store], :access_filter => af)
    assert_equal 1, q.instance_variable_get(:@ids_rel).to_sql.scan(/join .stores./i).size
  end
end
