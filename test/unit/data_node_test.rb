require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

describe Mochigome::DataNode do
  it "is a Hash" do
    assert Mochigome::DataNode.new(:foo, :bar).is_a?(Hash)
  end

  it "converts keys to symbols on creation" do
    datanode = Mochigome::DataNode.new(:foo, :bar, [{"a" => 1}, {"b" => 2}, {:c => 3}])
    assert_equal({:a => 1, :b => 2, :c => 3}, datanode)
  end

  it "converts its type name and name to strings on creation" do
    datanode = Mochigome::DataNode.new(:foo, :bar)
    assert_equal "foo", datanode.type_name
    assert_equal "bar", datanode.name
  end

  describe "when created empty" do
    before do
      @datanode = Mochigome::DataNode.new(:data, :john_doe)
    end

    it "has no comment" do
      assert_equal nil, @datanode.comment
    end

    it "can get a comment" do
      @datanode.comment = "We are the Knights of Ni!"
      assert_equal "We are the Knights of Ni!", @datanode.comment
    end

    it "can merge content from an array of single-item hashes" do
      @datanode.merge! [{:foo => 42}, {"bar" => 84}]
      assert_equal 42, @datanode[:foo]
      assert_equal 84, @datanode[:bar]
    end

    it "can have child nodes added to the top layer" do
      @datanode << Mochigome::DataNode.new(:subdata, :alice, {:a => 1, :b => 2})
      @datanode << Mochigome::DataNode.new(:subdata, :bob, {:a => 3, :b => 4})
      assert_equal 2, @datanode.children.size
      assert_equal({:a => 1, :b => 2}, @datanode.children.first)
    end

    it "can accept an array of children" do
      @datanode << [
        Mochigome::DataNode.new(:subdata, :alice, {:a => 1, :b => 2}),
        Mochigome::DataNode.new(:subdata, :bob, {:a => 3, :b => 4})
      ]
      assert_equal 2, @datanode.children.size
      assert_equal({:a => 1, :b => 2}, @datanode.children.first)
    end

    it "can have items added at multiple layers" do
      @datanode << Mochigome::DataNode.new(:subdata, :alice, {:a => 1, :b => 2})
      @datanode.children.first << Mochigome::DataNode.new(:subsubdata, :spot, {:x => 10, :y => 20})
      @datanode.children.first << Mochigome::DataNode.new(:subsubdata, :fluffy, {:x => 100, :y => 200})
      assert_equal 1, @datanode.children.size
      assert_equal 2, @datanode.children.first.size
      assert_equal({:x => 10, :y => 20}, @datanode.children.first.children.first)
    end

    it "cannot accept children that are not DataNodes" do
      assert_raises Mochigome::DataNodeError do
        @datanode << {:x => 1, :y => 2}
      end
    end

    it "returns the new child DataNode(s) from a concatenation" do
      new_child = @datanode << Mochigome::DataNode.new(:subdata, :alce, {:a => 1})
      assert_equal @datanode.children.first, new_child

      new_children = @datanode << [
        Mochigome::DataNode.new(:subdata, :bob, {:a => 1}),
        Mochigome::DataNode.new(:subdata, :charlie, {:a => 2})
      ]
      assert_equal @datanode.children.drop(1), new_children
    end

    it "understands forward-slash to mean indexing in children" do
      @datanode << Mochigome::DataNode.new(:subdata, :alice)
      @datanode << Mochigome::DataNode.new(:subdata, :bob)
      assert_equal @datanode.children[0], @datanode/0
      assert_equal @datanode.children[1], @datanode/1
    end
  end

  describe "when populated" do
    before do
      @datanode = Mochigome::DataNode.new(:corporation, :acme)
      @datanode.comment = "Foo"
      @datanode.merge! [{:id => 400}, {:apples => 1}, {:box_cutters => 2}, {:can_openers => 3}]
      emp1 = @datanode << Mochigome::DataNode.new(:employee, :alice)
      emp1.merge! [{:id => 500}, {:x => 9}, {:y => 8}, {:z => 7}, {:internal_type => "Cyborg"}]
      emp2 = @datanode << Mochigome::DataNode.new(:employee, :bob)
      emp2.merge! [{:id => 600}, {:x => 5}, {:y => 4}, {:z => 8734}, {:internal_type => "Human"}]
      emp2 << Mochigome::DataNode.new(:pet, :lassie)

      @titles = [
        "corporation::name",
        "corporation::id",
        "corporation::apples",
        "corporation::box_cutters",
        "corporation::can_openers",
        "employee::name",
        "employee::id",
        "employee::x",
        "employee::y",
        "employee::z",
        "employee::internal_type",
        "pet::name"
      ]
    end

    it "can convert to an XML document with ids, names, types, and internal_types as attributes" do
      # Why stringify and reparse it? So that we could switch to another XML generator.
      doc = Nokogiri::XML(@datanode.to_xml.to_s)

      comment = doc.xpath('/node[@type="Corporation"]/comment()').first
      assert comment
      assert comment.comment?
      assert_equal "Foo", comment.content

      assert_equal "400", doc.xpath('/node[@type="Corporation"]').first['id']
      assert_equal "2", doc.xpath('/node/datum[@name="Box Cutters"]').first.content

      emp_nodes = doc.xpath('/node/node[@type="Employee"]')
      assert_equal "500", emp_nodes.first['id']
      assert_equal "alice", emp_nodes.first['name']
      assert_equal "bob", emp_nodes.last['name']
      assert_equal "Cyborg", emp_nodes.first['internal_type']
      assert_equal "4", emp_nodes.last.xpath('./datum[@name="Y"]').first.content
      assert_equal "lassie", emp_nodes.last.xpath('node').first['name']
    end

    it "can convert to a flattened Ruport table" do
      table = @datanode.to_flat_ruport_table
      assert_equal @titles, table.column_names
      assert_equal ['acme', 400, 1, 2, 3, 'alice', 500,  9, 8, 7, "Cyborg", nil], table.data[0].to_a
      assert_equal ['acme', 400, 1, 2, 3, 'bob', 600, 5, 4, 8734, "Human", "lassie"], table.data[1].to_a
    end

    it "can convert to a flat array of arrays" do
      a = @datanode.to_flat_arrays
      assert_equal @titles, a[0]
      assert_equal ['acme', 400, 1, 2, 3, 'alice', 500, 9, 8, 7, "Cyborg", nil], a[1]
      assert_equal ['acme', 400, 1, 2, 3, 'bob', 600, 5, 4, 8734, "Human", "lassie"], a[2]
    end
  end
end
