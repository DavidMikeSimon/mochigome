require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

describe Mochigome::DataNode do
  it "is a Hash" do
    assert Mochigome::DataNode.new(:foo).is_a?(Hash)
  end

  it "converts keys to symbols on creation" do
    datanode = Mochigome::DataNode.new(:foo, [{"a" => 1}, {"b" => 2}, {:c => 3}])
    assert_equal({:a => 1, :b => 2, :c => 3}, datanode)
  end

  it "converts its type_name to a symbol on creation" do
    datanode = Mochigome::DataNode.new("foo")
    assert_equal :foo, datanode.type_name
  end

  describe "when created empty" do
    before do
      @datanode = Mochigome::DataNode.new(:data)
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
      @datanode << Mochigome::DataNode.new(:subdata, {:a => 1, :b => 2})
      @datanode << Mochigome::DataNode.new(:subdata, {:a => 3, :b => 4})
      assert_equal 2, @datanode.children.size
      assert_equal({:a => 1, :b => 2}, @datanode.children.first)
    end

    it "can accept an array of children" do
      @datanode << [
        Mochigome::DataNode.new(:subdata, {:a => 1, :b => 2}),
        Mochigome::DataNode.new(:subdata, {:a => 3, :b => 4})
      ]
      assert_equal 2, @datanode.children.size
      assert_equal({:a => 1, :b => 2}, @datanode.children.first)
    end

    it "can have items added at multiple layers" do
      @datanode << Mochigome::DataNode.new(:subdata, {:a => 1, :b => 2})
      @datanode.children.first << Mochigome::DataNode.new(:subsubdata, {:x => 10, :y => 20})
      @datanode.children.first << Mochigome::DataNode.new(:subsubdata, {:x => 100, :y => 200})
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
      new_child = @datanode << Mochigome::DataNode.new(:subdata, {:a => 1})
      assert_equal @datanode.children.first, new_child

      new_children = @datanode << [
        Mochigome::DataNode.new(:subdata, {:a => 1}),
        Mochigome::DataNode.new(:subdata, {:a => 2})
      ]
      assert_equal @datanode.children.drop(1), new_children
    end
  end

  describe "when populated" do
    before do
      @datanode = Mochigome::DataNode.new(:abc)
      @datanode.comment = "Foo"
      @datanode.merge! [{:id => 400}, {:a => 1}, {:b => 2}, {:c => 3}]
      xyz1 = @datanode << Mochigome::DataNode.new(:xyz)
      xyz1.merge! [{:id => 500}, {:x => 9}, {:y => 8}, {:z => 7}]
      xyz2 = @datanode << Mochigome::DataNode.new(:xyz)
      xyz2.merge! [{:id => 600}, {:x => 5}, {:y => 4}, {:z => 8734}]
    end

    it "can convert to an XML document with ids and heights as attributes" do
      # Why stringify and reparse it? So that we could switch to another XML generator.
      doc = Nokogiri::XML(@datanode.to_xml.to_s)

      comment = doc.xpath('/node[@type="abc"]/comment()').first
      assert comment
      assert comment.comment?
      assert_equal "Foo", comment.content

      assert_equal "400", doc.xpath('/node[@type="abc"]').first['id']
      assert_equal "1", doc.xpath('/node').first['height']
      assert_equal "2", doc.xpath('/node/datum[@name="b"]').first.content

      xyz_nodes = doc.xpath('/node/node[@type="xyz"]')
      assert_equal "500", xyz_nodes.first['id']
      assert_equal "0", xyz_nodes[0]['height']
      assert_equal "0", xyz_nodes[1]['height']
      assert_equal "4", xyz_nodes[1].xpath('./datum[@name="y"]').first.content
    end

    it "can convert to a flattened Ruport table" do
      table = @datanode.to_flat_ruport_table
      titles = [
        "abc::id",
        "abc::a",
        "abc::b",
        "abc::c",
        "xyz::id",
        "xyz::x",
        "xyz::y",
        "xyz::z"
      ]
      assert_equal titles, table.column_names
      assert_equal [400, 1, 2, 3, 500, 9, 8, 7], table.data[0].to_a
      assert_equal [400, 1, 2, 3, 600, 5, 4, 8734], table.data[1].to_a
    end
  end
end
