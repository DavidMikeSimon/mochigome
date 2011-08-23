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
    expected = [
      {:name => "a", :value => "abc"},
      {:name => "b", :value => "xyz"}
    ]
    assert_equal expected, i.report_focus.data
  end

  it "has no report focus data if no fields are specified" do
    @model_class.class_eval do
      acts_as_report_focus
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    assert_equal [], i.report_focus.data
  end

  it "can specify only some of its fields" do
    @model_class.class_eval do
      acts_as_report_focus do |f|
        f.fields ["b"]
      end
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    expected = [
      {:name => "b", :value => "xyz"}
    ]
    assert_equal expected, i.report_focus.data
  end

  it "can specify fields in a custom order" do
    @model_class.class_eval do
      acts_as_report_focus do |f|
        f.fields ["b", "a"]
      end
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    expected = [
      {:name => "b", :value => "xyz"},
      {:name => "a", :value => "abc"}
    ]
    assert_equal expected, i.report_focus.data
  end

  it "can specify fields with multiple calls" do
    @model_class.class_eval do
      acts_as_report_focus do |f|
        f.fields ["a"]
        f.fields ["b"]
      end
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    expected = [
      {:name => "a", :value => "abc"},
      {:name => "b", :value => "xyz"}
    ]
    assert_equal expected, i.report_focus.data
  end

  it "can specify fields with custom names" do
    @model_class.class_eval do
      acts_as_report_focus do |f|
        f.fields [{:Abraham => :a}, {:Barcelona => :b}]
      end
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    expected = [
      {:name => "Abraham", :value => "abc"},
      {:name => "Barcelona", :value => "xyz"}
    ]
    assert_equal expected, i.report_focus.data
  end

  it "can specify fields with custom implementations" do
    @model_class.class_eval do
      acts_as_report_focus do |f|
        f.fields [{:concat => lambda {|obj| obj.a + obj.b}}]
      end
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    assert_equal [{:name => "concat", :value => "abcxyz"}], i.report_focus.data
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
end