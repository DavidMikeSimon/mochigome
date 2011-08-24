require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

describe Ernie::DataNode do
  it "is a Hash" do
    assert Ernie::DataNode.new(:foo).is_a?(Hash)
  end

  it "converts keys to symbols on creation" do
    datanode = Ernie::DataNode.new(:foo, {"a" => 1, "b" => 2, :c => 3})
    assert_equal({:a => 1, :b => 2, :c => 3}, datanode)
  end

  it "converts its type_name to a symbol on creation" do
    datanode = Ernie::DataNode.new("foo")
    assert_equal :foo, datanode.type_name
  end

  describe "when created empty" do
    before do
      @datanode = Ernie::DataNode.new(:data)
    end

    it "can merge content from an array of single-item hashes" do
      @datanode.merge! [{:foo => 42}, {"bar" => 84}]
      assert_equal 42, @datanode[:foo]
      assert_equal 84, @datanode[:bar]
    end

    it "can have child nodes added to the top layer" do
      @datanode << Ernie::DataNode.new(:subdata, {:a => 1, :b => 2})
      @datanode << Ernie::DataNode.new(:subdata, {:a => 3, :b => 4})
      assert_equal 2, @datanode.children.size
      assert_equal({:a => 1, :b => 2}, @datanode.children.first)
    end

    it "can accept an array of children" do
      @datanode << [
        Ernie::DataNode.new(:subdata, {:a => 1, :b => 2}),
        Ernie::DataNode.new(:subdata, {:a => 3, :b => 4})
      ]
      assert_equal 2, @datanode.children.size
      assert_equal({:a => 1, :b => 2}, @datanode.children.first)
    end

    it "can have items added at multiple layers" do
      @datanode << Ernie::DataNode.new(:subdata, {:a => 1, :b => 2})
      @datanode.children.first << Ernie::DataNode.new(:subsubdata, {:x => 10, :y => 20})
      @datanode.children.first << Ernie::DataNode.new(:subsubdata, {:x => 100, :y => 200})
      assert_equal 1, @datanode.children.size
      assert_equal 2, @datanode.children.first.size
      assert_equal({:x => 10, :y => 20}, @datanode.children.first.children.first)
    end

    it "cannot accept children that are not DataNodes" do
      assert_raises Ernie::DataNodeError do
        @datanode << {:x => 1, :y => 2}
      end
    end

    it "returns the new child DataNode(s) from a concatenation" do
      new_child = @datanode << Ernie::DataNode.new(:subdata, {:a => 1})
      assert_equal @datanode.children.first, new_child

      new_children = @datanode << [
        Ernie::DataNode.new(:subdata, {:a => 1}),
        Ernie::DataNode.new(:subdata, {:a => 2})
      ]
      assert_equal @datanode.children.drop(1), new_children
    end
  end

  describe "when populated" do
    before do
      @datanode = Ernie::DataNode.new(:abc)
      @datanode.merge! [{:id => 400}, {:a => 1}, {:b => 2}, {:c => 3}]
      xyz1 = @datanode << Ernie::DataNode.new(:xyz)
      xyz1.merge! [{:id => 500}, {:x => 9}, {:y => 8}, {:z => 7}]
      xyz2 = @datanode << Ernie::DataNode.new(:xyz)
      xyz2.merge! [{:id => 600}, {:x => 5}, {:y => 4}, {:z => 8734}]
    end

    it "can convert to an XML document with ids as attributes" do
      # Why stringify and reparse it? So that we could switch to another XML generator.
      doc = Nokogiri::XML(@datanode.to_xml.to_s)
      assert_equal "400", doc.xpath('//abc').first['id']
      assert_equal "2", doc.xpath('//abc/b').first.content
      xyz_nodes = doc.xpath('//abc/xyz')
      assert_equal "500", xyz_nodes.first['id']
      assert_equal "4", xyz_nodes[1].xpath(".//y").first.content
    end

    it "can convert to a flattened Ruport table" do
      table = @datanode.to_ruport_table
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
