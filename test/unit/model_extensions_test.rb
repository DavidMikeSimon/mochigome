require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

describe "an input string" do
  it "will be converted by auto_numerify to an integer if appropriate" do
    [35, -35, 0].each do |n|
      result = Mochigome::ReportFocus.auto_numerify(n.to_s)
      assert_equal n, result
      assert_kind_of Integer, result
    end
  end

  it "will be converted by auto_numerify to a float if appropriate" do
    [-35.5, 35.5, 0.0].each do |n|
      result = Mochigome::ReportFocus.auto_numerify(n.to_s)
      assert_in_delta n, result
      assert_kind_of Float, result
    end
  end

  it "will remain a string if it is not numeric" do
    ["", "zero", "yeehah", "foo0.0" "9.2bar"].each do |s|
      result = Mochigome::ReportFocus.auto_numerify(s)
      assert_equal s, result
      assert_kind_of String, result
    end
  end
end

describe "an ActiveRecord model" do
  before do
    @model_class = Class.new(ActiveRecord::Base)
    @model_class.class_eval do
      set_table_name :fake
      def name
        "Moby"
      end
      def last_name
        "Dick"
      end
    end
    Whale = @model_class
  end

  after do
    Object.send(:remove_const, :Whale)
  end

  it "indicates if it acts_as_mochigome_focus or not" do
    refute @model_class.acts_as_mochigome_focus?
    @model_class.class_eval do
      acts_as_mochigome_focus
    end
    assert @model_class.acts_as_mochigome_focus?
  end

  it "cannot call acts_as_mochigome_focus more than once" do
    @model_class.class_eval do
      acts_as_mochigome_focus
    end
    assert_raises Mochigome::ModelSetupError do
      @model_class.class_eval do
        acts_as_mochigome_focus
      end
    end
  end

  it "inherits a parent's report focus settings" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.type_name "Foobar"
      end
    end
    @sub_class = Class.new(@model_class)
    i = @sub_class.new
    assert_equal "Foobar", i.mochigome_focus.type_name
  end

  it "can override a parent's report focus settings" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.type_name "Foobar"
      end
    end
    @sub_class = Class.new(@model_class)
    @sub_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.type_name "Narfbork"
      end
    end
    i = @sub_class.new
    assert_equal "Narfbork", i.mochigome_focus.type_name
  end

  it "uses its class name as the default type name" do
    @model_class.class_eval do
      acts_as_mochigome_focus
    end
    i = @model_class.new
    assert_equal "Whale", i.mochigome_focus.type_name.split("::").last
  end

  it "can override the default type name" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.type_name "Thingie"
      end
    end
    i = @model_class.new
    assert_equal "Thingie", i.mochigome_focus.type_name
  end

  it "cannot specify a nonsense type name" do
    assert_raises Mochigome::ModelSetupError do
      @model_class.class_eval do
        acts_as_mochigome_focus do |f|
          f.type_name 12345
        end
      end
    end
  end

  it "uses the attribute 'name' as the default focus name" do
    @model_class.class_eval do
      acts_as_mochigome_focus
    end
    i = @model_class.new
    assert_equal "Moby", i.mochigome_focus.name
  end

  it "can override the focus name with another method_name" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.name :last_name
      end
    end
    i = @model_class.new
    assert_equal "Dick", i.mochigome_focus.name
  end

  it "can override the focus name with a custom implementation" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.name lambda {|obj| "#{obj.name} #{obj.last_name}"}
      end
    end
    i = @model_class.new
    assert_equal "Moby Dick", i.mochigome_focus.name
  end

  it "can specify fields" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.fields ["a", "b"]
      end
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    expected = ActiveSupport::OrderedHash.new
    expected["a"] = "abc"
    expected["b"] = "xyz"
    assert_equal expected, i.mochigome_focus.field_data
  end

  it "has no report focus data if no fields are specified" do
    @model_class.class_eval do
      acts_as_mochigome_focus
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    assert_empty i.mochigome_focus.field_data
  end

  it "can specify only some of its fields" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.fields ["b"]
      end
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    expected = ActiveSupport::OrderedHash.new
    expected["b"] = "xyz"
    assert_equal expected, i.mochigome_focus.field_data
  end

  it "can specify fields in a custom order" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.fields ["b", "a"]
      end
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    expected = ActiveSupport::OrderedHash.new
    expected["b"] = "xyz"
    expected["a"] = "abc"
    assert_equal expected, i.mochigome_focus.field_data
  end

  it "can specify fields with multiple calls" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.fields ["a"]
        f.fields ["b"]
      end
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    expected = ActiveSupport::OrderedHash.new
    expected["a"] = "abc"
    expected["b"] = "xyz"
    assert_equal expected, i.mochigome_focus.field_data
  end

  it "can specify fields with custom names" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.fields [{:Abraham => :a}, {:Barcelona => :b}]
      end
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    expected = ActiveSupport::OrderedHash.new
    expected["Abraham"] = "abc"
    expected["Barcelona"] = "xyz"
    assert_equal expected, i.mochigome_focus.field_data
  end

  it "can specify fields with custom implementations" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.fields [{:concat => lambda {|obj| obj.a + obj.b}}]
      end
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    expected = ActiveSupport::OrderedHash.new
    expected["concat"] = "abcxyz"
    assert_equal expected, i.mochigome_focus.field_data
  end

  it "cannot call f.fields with nonsense" do
    assert_raises Mochigome::ModelSetupError do
      @model_class.class_eval do
        acts_as_mochigome_focus do |f|
          f.fields 123
        end
      end
    end
    assert_raises Mochigome::ModelSetupError do
      @model_class.class_eval do
        acts_as_mochigome_focus do |f|
          f.fields [789]
        end
      end
    end
  end

  [:name, :id, :type, :internal_type].each do |n|
    it "cannot specify fields named the same as reserved term '#{n}'" do
      assert_raises Mochigome::ModelSetupError do
        @model_class.class_eval do
          acts_as_mochigome_focus do |f|
            f.fields [n]
          end
        end
      end
      assert_raises Mochigome::ModelSetupError do
        @model_class.class_eval do
          acts_as_mochigome_focus do |f|
            f.fields [n.to_s.titleize]
          end
        end
      end
      assert_raises Mochigome::ModelSetupError do
        @model_class.class_eval do
          acts_as_mochigome_focus do |f|
            f.fields [{n => :foo}]
          end
        end
      end
    end
  end

  it "appears in Mochigome's global model list if it acts_as_mochigome_focus" do
    assert !Mochigome.reportFocusModels.include?(@model_class)
    @model_class.class_eval do
      acts_as_mochigome_focus
    end
    assert Mochigome.reportFocusModels.include?(@model_class)
  end

  it "can specify aggregated data to be collected" do
    @model_class.class_eval do
      has_mochigome_aggregations [
        :average_x,
        :Count,
        {"bloo" => :sum_x}
      ]
    end
    # The actual effectiveness of these lambdas will be tested in query_test.
    assert_equal [
      "Whales average x",
      "Whales Count",
      "Whales sum x"
    ], @model_class.mochigome_aggregations.map{|a| a[:name]}
  end

  it "can specify aggregations with custom names" do
    @model_class.class_eval do
      has_mochigome_aggregations [{"Mean X" => "avg x"}]
    end
    assert_equal [
      "Mean X"
    ], @model_class.mochigome_aggregations.map{|a| a[:name]}
  end

  it "can specify aggregations with custom arel expressions" do
    @model_class.class_eval do
      has_mochigome_aggregations [{"The Answer" => lambda{|r| }}]
    end
    assert_equal [
      "The Answer"
    ], @model_class.mochigome_aggregations.map{|a| a[:name]}
  end

  it "cannot call has_mochigome_aggregations with nonsense" do
    assert_raises Mochigome::ModelSetupError do
      @model_class.class_eval do
        has_mochigome_aggregations 3
      end
    end
    assert_raises Mochigome::ModelSetupError do
      @model_class.class_eval do
        has_mochigome_aggregations [42]
      end
    end
  end

  it "can convert an association into an arel relation" do
    flunk
  end
end
