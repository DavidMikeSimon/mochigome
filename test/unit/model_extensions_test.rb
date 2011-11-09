require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

describe "an ActiveRecord model" do
  before do
    @model_class = Class.new(ActiveRecord::Base)
    @model_class.class_eval do
      set_table_name :fake
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
        f.name "Foobar"
      end
    end
    @sub_class = Class.new(@model_class)
    i = @sub_class.new
    assert_equal "Foobar", i.mochigome_focus.name
  end

  it "can override a parent's report focus settings" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.name "Foobar"
      end
    end
    @sub_class = Class.new(@model_class)
    @sub_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.name "Narfbork"
      end
    end
    i = @sub_class.new
    assert_equal "Narfbork", i.mochigome_focus.name
  end

  it "uses its class name as the default group name" do
    @model_class.class_eval do
      acts_as_mochigome_focus
    end
    i = @model_class.new
    assert_equal "Whale", i.mochigome_focus.name.split("::").last
  end

  it "can override the default group name" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.name "Thingie"
      end
    end
    i = @model_class.new
    assert_equal "Thingie", i.mochigome_focus.name
  end

  it "cannot specify a nonsense group name" do
    assert_raises Mochigome::ModelSetupError do
      @model_class.class_eval do
        acts_as_mochigome_focus do |f|
          f.name 12345
        end
      end
    end
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
