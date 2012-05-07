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

    (1..5).each do |div_num|
      WidgetDivisor.create(:divisor => div_num)
    end

    (1..25).each do |num|
      Widget.create(:number => num)
    end
  end

  after do
    Category.delete_all
    Product.delete_all
    Owner.delete_all
    Store.delete_all
    StoreProduct.delete_all
    Sale.delete_all
    WidgetDivisor.delete_all
    Widget.delete_all
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

  it "returns all possible results if no conditions given" do
    q = Mochigome::Query.new([Category, Product])
    data_node = q.run()
    assert_equal 2, data_node.children.size
    assert_equal 4, (data_node/0).children.size + (data_node/1).children.size
  end

  it "can build a one-layer DataNode given an object with an id to focus on" do
    q = Mochigome::Query.new([Product])
    data_node = q.run(@product_a)
    assert_equal_children [@product_a], data_node
    assert_no_children data_node/0
  end

  it "can build a one-layer DataNode when given an arbitrary Arel condition" do
    q = Mochigome::Query.new([Product])
    data_node = q.run(Product.arel_table[:name].eq(@product_a.name))
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

  it "can subgroup layers by attributes" do
    q = Mochigome::Query.new(
      [Mochigome::SubgroupModel.new(Owner, :last_name), Owner, Store, Product]
    )
    data_node = q.run
    assert_equal "Smith", (data_node/1).name
    assert_equal "John Smith", (data_node/1/0).name
    assert_equal "John's Store", (data_node/1/0/0).name
    assert_equal "Product A", (data_node/1/0/0/0).name
  end

  it "can subgroup layers by attributes without including layer model" do
    q = Mochigome::Query.new(
      [Mochigome::SubgroupModel.new(Owner, :last_name)],
      :aggregate_sources => [Sale]
    )
    data_node = q.run
    assert_equal "Smith", (data_node/1).name
    assert_equal 8, (data_node/1)['Sales count']
  end

  it "can subgroup layers with custom expressions" do
    q = Mochigome::Query.new(
      [
        Store,
        Mochigome::SubgroupModel.new(Product, :name_ends_with_vowel),
        Product
      ]
    )
    data_node = q.run
    assert_equal "Jane's Store (North)", (data_node/1).name
    assert_equal "Consonant", (data_node/1/0).name
    assert_equal 1, (data_node/1/0).children.size
    assert_equal "Vowel", (data_node/1/1).name
    assert_equal 2, (data_node/1/1).children.size
  end

  it "can collect aggregate data with custom expression subgroups" do
    q = Mochigome::Query.new(
      [
        Store,
        Mochigome::SubgroupModel.new(Product, :name_ends_with_vowel),
      ],
      :aggregate_sources => [Product]
    )
    data_node = q.run
    assert_equal "Jane's Store (North)", (data_node/1).name
    assert_equal "Consonant", (data_node/1/0).name
    assert_equal @product_b.price, (data_node/1/0)['Products sum price']
    assert_equal "Vowel", (data_node/1/1).name
    assert_equal [@product_a, @product_e].map(&:price).sum,
      (data_node/1/1)['Products sum price']
  end

  it "can group through a list that has no direct association path" do
    q = Mochigome::Query.new(
      [Category, Store, Product],
      :aggregate_sources => [Sale]
    )
    data_node = q.run
    assert_equal "Category 1", (data_node/0).name
    assert_equal 15, (data_node/0)["Sales count"]
    assert_equal "John's Store", (data_node/0/0).name
    assert_equal 5, (data_node/0/0)["Sales count"]
    assert_equal "Product A", (data_node/0/0/0).name
    assert_equal 5, (data_node/0/0/0)["Sales count"]
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
    assert_equal (3*@product_c.price).to_s, (data_node/0/0/1)['Gross'].to_s
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
    assert_equal (2*@product_c.price).to_s, (data_node/1/0/0)['Gross'].to_s
  end

  it "collects aggregate data in subgroups" do
    q = Mochigome::Query.new(
      [Mochigome::SubgroupModel.new(Owner, :last_name), Owner, Store, Product],
      :aggregate_sources => [[Product, Sale]]
    )
    data_node = q.run

    assert_equal "Smith", (data_node/1).name
    assert_equal 8, (data_node/1)['Sales count']
    assert_equal "John Smith", (data_node/1/0).name
    assert_equal 8, (data_node/1/0)['Sales count']
    assert_equal "John's Store", (data_node/1/0/0).name
    assert_equal 8, (data_node/1/0/0)['Sales count']
    assert_equal "Product A", (data_node/1/0/0/0).name
    assert_equal 5, (data_node/1/0/0/0)['Sales count']
  end

  it "collects aggregate data in subgroups going farther than layer list" do
    q = Mochigome::Query.new(
      [Mochigome::SubgroupModel.new(Owner, :last_name), Owner, Store],
      :aggregate_sources => [[Product, Sale]]
    )
    data_node = q.run

    assert_equal "Smith", (data_node/1).name
    assert_equal 8, (data_node/1)['Sales count']
    assert_equal "John Smith", (data_node/1/0).name
    assert_equal 8, (data_node/1/0)['Sales count']
    assert_equal "John's Store", (data_node/1/0/0).name
    assert_equal 8, (data_node/1/0/0)['Sales count']
  end

  it "collects aggregate data using data model as focus if focus not supplied" do
    q = Mochigome::Query.new(
      [Owner, Store, Product],
      :aggregate_sources => [Sale]
    )

    data_node = q.run

    assert_equal "Jane's Store (North)", (data_node/1/0).name
    assert_equal 11, (data_node/1/0)['Sales count']

    assert_equal "Jane Doe", (data_node/1).name
    assert_equal 16, (data_node/1)['Sales count']

    assert_equal 24, data_node['Sales count']
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

  it "collects aggregate data on layers above the focus when given no condition" do
    q = Mochigome::Query.new(
      [Owner, Store, Product],
      :aggregate_sources => [[Product, Sale]]
    )
    data_node = q.run

    assert_equal "Jane's Store (North)", (data_node/1/0).name
    assert_equal 11, (data_node/1/0)['Sales count']

    assert_equal "Jane Doe", (data_node/1).name
    assert_equal 16, (data_node/1)['Sales count']

    assert_equal 24, data_node['Sales count']
  end

  it "goes farther than layer list to include aggregate focus" do
    q = Mochigome::Query.new(
      [Owner, Store],
      :aggregate_sources => [[Product, Sale]]
    )
    data_node = q.run

    assert_equal "Jane's Store (North)", (data_node/1/0).name
    assert_equal 11, (data_node/1/0)['Sales count']

    assert_equal "Jane Doe", (data_node/1).name
    assert_equal 16, (data_node/1)['Sales count']

    assert_equal 24, data_node['Sales count']
  end

  it "can collect aggregate data involving joins to tables not on path" do
    q = Mochigome::Query.new(
      [Owner, Store],
      :aggregate_sources => [Sale]
    )

    data_node = q.run()
    assert_equal "John's Store", (data_node/0/0).name
    assert_equal 8, (data_node/0/0)['Sales count']
    assert_equal (5*@product_a.price + 3*@product_c.price).to_s,
      (data_node/0/0)['Gross'].to_s
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

  it "can do sums" do
    q = Mochigome::Query.new(
      [Owner, Store],
      :aggregate_sources => [[Store, Product]]
    )
    data_node = q.run([@john])
    assert_equal (@product_a.price + @product_c.price),
      data_node['Products sum price']
  end

  it "still does conditional counts correctly when joins below focus used" do
    af = proc do |cls|
      return {} unless cls == Product
      return {
        :join_paths => [[Product, StoreProduct, Store]]
      }
    end
    q = Mochigome::Query.new(
      [Category],
      :aggregate_sources => [[Category, Product]],
      :access_filter => af
    )
    data_node = q.run([@category1, @category2])
    assert_equal 1, (data_node/0)['Expensive products']
    assert_equal 2, (data_node/1)['Expensive products']
  end

  it "still does sums correctly when joins below focus are used" do
    af = proc do |cls|
      return {} unless cls == Store
      return {
        :join_paths => [[Store, StoreProduct, Sale]]
      }
    end
    q = Mochigome::Query.new(
      [Owner, Store],
      :aggregate_sources => [[Store, Product]],
      :access_filter => af
    )
    data_node = q.run([@john])
    assert_equal (@product_a.price + @product_c.price),
      data_node['Products sum price']
  end

  it "allows grouping and aggregation on same class with another condition" do
    # This query is a pointless use of aggregates, but it still shouldn't
    # crash, which it has when similar queries were ran in JSAS.
    q = Mochigome::Query.new(
      [Product],
      :aggregate_sources => [Product]
    )
    data_node = q.run([@store_x])
    assert_equal 1, data_node["Expensive products"]
  end

  it "routes correctly from subgrouping to condition models" do
    q = Mochigome::Query.new(
      [Mochigome::SubgroupModel.new(Owner, :last_name)]
    )
    data_node = q.run([@product_a, @product_b])
    assert_equal "Smith", (data_node/1).name
  end

  it "does not include hidden aggregation fields in output" do
    q = Mochigome::Query.new(
      [Owner, Store],
      :aggregate_sources => [[Store, Product]]
    )
    data_node = q.run([@john])
    refute data_node.has_key?('Secret count')
  end

  it "correctly runs aggregation fields implemented in ruby" do
    q = Mochigome::Query.new(
      [Owner, Store],
      :aggregate_sources => [[Store, Product]]
    )
    data_node = q.run([@john])
    assert_equal 4, data_node["Count squared"]
  end

  # TODO: Test use of non-trivial function for aggregation value

  it "puts a comment on the root node describing the query" do
    q = Mochigome::Query.new([Owner, Store, Product])
    data_node = q.run([@store_x, @store_y, @store_z])
    c = data_node.comment
    assert_match c, /^Mochigome Version: #{Mochigome::VERSION}\n/
    assert_match c, /\nReport Generated: \w{3} \w{3} \d+ .+\n/
    assert_match c, /\nLayers: Owner => Store => Product\n/
    assert_match c, /\nJoin: \w+ -> \w+\n/
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

  it "can use a provided access filter function to limit query results" do
    af = proc do |cls|
      return {} unless cls == Product
      return {
        :condition => Product.arel_table[:category_id].gt(0)
      }
    end
    q = Mochigome::Query.new([Product], :access_filter => af)
    dn = q.run
    assert_equal 4, dn.children.size
    refute dn.children.any?{|c| c.name == "Product E"}
  end

  it "can do joins at the request of an access filter" do
    af = proc do |cls|
      return {} unless cls == Product
      return {
        :join_paths => [[Product, StoreProduct, Store]],
        :condition => Store.arel_table[:name].matches("Jo%")
      }
    end
    q = Mochigome::Query.new([Product], :access_filter => af)
    dn = q.run
    assert_equal 2, dn.children.size
    refute dn.children.any?{|c| c.name == "Product E"}
  end

  it "access filter joins will not duplicate joins already in the query" do
    af = proc do |cls|
      return {} unless cls == Product
      return {
        :join_paths => [[Product, StoreProduct, Store]],
        :condition => Store.arel_table[:name].matches("Jo%")
      }
    end
    q = Mochigome::Query.new([Product, Store], :access_filter => af)
    assert_equal 1, q.instance_variable_get(:@ids_rel).to_sql.scan(/join .stores./i).size
  end

  it "automatically joins if run given a condition on a new table" do
    q = Mochigome::Query.new([Product, Store])
    dn = q.run(Category.arel_table[:name].eq(@category1.name))
    assert_equal 2, dn.children.size
  end

  it "uses default values for aggregations on an empty result set" do
    Sale.destroy_all
    q = Mochigome::Query.new(
      [Store, Product],
      :aggregate_sources => [[Product, Sale]]
    )
    dn = q.run
    assert_equal 3, dn.children.size
    assert_equal 0, dn['Gross']
    assert_equal 0, (dn/0)['Gross']
    assert_equal 0, (dn/0/0)['Gross']
  end

  it "can use custom associations to link records" do
    q = Mochigome::Query.new([WidgetDivisor, Widget])
    dn = q.run
    assert_equal "Divisor 1", (dn/0).name
    assert_equal 25, (dn/0).children.size
    assert_equal "Divisor 2", (dn/1).name
    assert_equal 12, (dn/1).children.size
    assert_equal "Divisor 5", (dn/4).name
    assert_equal 5, (dn/4).children.size
  end

  it "can follow custom associations in reverse" do
    q = Mochigome::Query.new([Widget, WidgetDivisor])
    dn = q.run
    assert_equal "Widget 1", (dn/0).name
    assert_equal 1, (dn/0).children.size
    assert_equal "Widget 6", (dn/5).name
    assert_equal 3, (dn/5).children.size
  end
end
