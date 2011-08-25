require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

describe "an ActiveRecord model" do
  before do
    @model_class = Class.new(ActiveRecord::Base)
    @model_class.class_eval do
      set_table_name :fake
    end
  end

  it "indicates if it acts_as_report_focus or not" do
    refute @model_class.acts_as_report_focus?
    @model_class.class_eval do
      acts_as_report_focus
    end
    assert @model_class.acts_as_report_focus?
  end

  it "cannot call acts_as_report_focus more than once" do
    @model_class.class_eval do
      acts_as_report_focus
    end
    assert_raises Ernie::ModelSetupError do
      @model_class.class_eval do
        acts_as_report_focus
      end
    end
  end

  it "inherits a parent's report focus settings" do
    @model_class.class_eval do
      acts_as_report_focus do |f|
        f.group_name "Foobar"
      end
    end
    @sub_class = Class.new(@model_class)
    i = @sub_class.new
    assert_equal "Foobar", i.report_focus.group_name
  end

  it "can override a parent's report focus settings" do
    @model_class.class_eval do
      acts_as_report_focus do |f|
        f.group_name "Foobar"
      end
    end
    @sub_class = Class.new(@model_class)
    @sub_class.class_eval do
      acts_as_report_focus do |f|
        f.group_name "Narfbork"
      end
    end
    i = @sub_class.new
    assert_equal "Narfbork", i.report_focus.group_name
  end
  
  it "uses its class name as the default group name" do
    Foobar = @model_class 
    Foobar.class_eval do
      acts_as_report_focus
    end
    i = Foobar.new
    assert_equal "Foobar", i.report_focus.group_name.split("::").last
  end

  it "can override the default group name" do
    @model_class.class_eval do
      acts_as_report_focus do |f|
        f.group_name "Thingie"
      end
    end
    i = @model_class.new
    assert_equal "Thingie", i.report_focus.group_name
  end

  it "cannot specify a nonsense group name" do
    assert_raises Ernie::ModelSetupError do
      @model_class.class_eval do
        acts_as_report_focus do |f|
          f.group_name 12345
        end
      end
    end
  end

  it "can specify fields" do
    @model_class.class_eval do
      acts_as_report_focus do |f|
        f.fields ["a", "b"]
      end
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    expected = ActiveSupport::OrderedHash.new
    expected["a"] = "abc"
    expected["b"] = "xyz"
    assert_equal expected, i.report_focus.field_data
  end

  it "has no report focus data if no fields are specified" do
    @model_class.class_eval do
      acts_as_report_focus
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    assert_empty i.report_focus.field_data
  end

  it "can specify only some of its fields" do
    @model_class.class_eval do
      acts_as_report_focus do |f|
        f.fields ["b"]
      end
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    expected = ActiveSupport::OrderedHash.new
    expected["b"] = "xyz"
    assert_equal expected, i.report_focus.field_data
  end

  it "can specify fields in a custom order" do
    @model_class.class_eval do
      acts_as_report_focus do |f|
        f.fields ["b", "a"]
      end
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    expected = ActiveSupport::OrderedHash.new
    expected["b"] = "xyz"
    expected["a"] = "abc"
    assert_equal expected, i.report_focus.field_data
  end

  it "can specify fields with multiple calls" do
    @model_class.class_eval do
      acts_as_report_focus do |f|
        f.fields ["a"]
        f.fields ["b"]
      end
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    expected = ActiveSupport::OrderedHash.new
    expected["a"] = "abc"
    expected["b"] = "xyz"
    assert_equal expected, i.report_focus.field_data
  end

  it "can specify fields with custom names" do
    @model_class.class_eval do
      acts_as_report_focus do |f|
        f.fields [{:Abraham => :a}, {:Barcelona => :b}]
      end
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    expected = ActiveSupport::OrderedHash.new
    expected["Abraham"] = "abc"
    expected["Barcelona"] = "xyz"
    assert_equal expected, i.report_focus.field_data
  end

  it "can specify fields with custom implementations" do
    @model_class.class_eval do
      acts_as_report_focus do |f|
        f.fields [{:concat => lambda {|obj| obj.a + obj.b}}]
      end
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    expected = ActiveSupport::OrderedHash.new
    expected["concat"] = "abcxyz"
    assert_equal expected, i.report_focus.field_data
  end

  it "cannot call f.fields with nonsense" do
    assert_raises Ernie::ModelSetupError do
      @model_class.class_eval do
        acts_as_report_focus do |f|
          f.fields 123
        end
      end
    end
    assert_raises Ernie::ModelSetupError do
      @model_class.class_eval do
        acts_as_report_focus do |f|
          f.fields [789]
        end
      end
    end
  end

  it "appears in Ernie's global model list if it acts_as_report_focus" do
    assert !Ernie.reportFocusModels.include?(@model_class)
    @model_class.class_eval do
      acts_as_report_focus
    end
    assert Ernie.reportFocusModels.include?(@model_class)
  end

  it "can specify aggregated data to be collected" do
    @model_class.class_eval do
      has_report_aggregations [:average_x, :Count, "sum x"]
    end
    # Peeking in past API to make sure it set the expressions correctly
    assert_equal [
      {:name => "average_x", :expr => "avg(x)"},
      {:name => "Count", :expr => "count()"},
      {:name => "sum x", :expr => "sum(x)"}
    ], @model_class.ernie_aggregations
  end

  describe "with some aggregatable data" do
    before do
      @store1 = create(:store)
      @store2 = create(:store)
      @product_a = create(:product, :name => "Product A", :price => 30)
      @product_b = create(:product, :name => "Product B", :price => 50)
      @sp1A = create(:store_product, :store => @store1, :product => @product_a)
      @sp1B = create(:store_product, :store => @store1, :product => @product_b)
      @sp2A = create(:store_product, :store => @store2, :product => @product_a)
      @sp2B = create(:store_product, :store => @store2, :product => @product_b)
      [
        [2, @sp1A],
        [4, @sp1B],
        [7, @sp2A],
        [3, @sp2B]
      ].each do |num, sp|
        num.times { create(:sale, :store_product => sp) }
      end
    end

    it "can collect aggregate data from a report focus through an association" do
      assert_equal 9, @product_a.report_focus.aggregate_data('sales')['sales_count']
      assert_equal 7, @product_b.report_focus.aggregate_data('sales')['sales_count']
    end

    it "can collect aggregate data through all known associations with :all keyword" do
      assert_equal 9, @product_a.report_focus.aggregate_data(:all)['sales_count']
    end

    it "returns both field data and all aggregate data with the data method" do
      data = @product_a.report_focus.data
      assert_equal 9, data['sales_count']
      assert_equal "Product A", data['name']
    end

    it "can return data aggregated in the context of another class with similar assoc" do
      focus = @product_a.report_focus
      assert_equal 2, focus.aggregate_data('sales', :context => [@sp1A])['sales_count']
    end

    it "can return data aggregated in the context through the data method" do
      focus = @product_a.report_focus
      assert_equal 2, focus.data(:context => [@sp1A])['sales_count']
    end
  end
end
