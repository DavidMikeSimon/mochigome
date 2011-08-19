require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

class TestModelExtensions < Test::Unit::TestCase
  context "an ActiveRecord model" do
    setup do
      @model_class = Class.new(ActiveRecord::Base)
      @model_class.class_eval do
        set_table_name :fake
      end
    end
    
    should "have a default tag name the same as its class name" do
      SomeWeirdConstant = @model_class 
      i = SomeWeirdConstant.new
      assert_equal "SomeWeirdConstant", i.ernie_tag_name.split("::").last
      TestModelExtensions.send(:remove_const, :SomeWeirdConstant)
    end

    should "be able to override the default tag name" do
      @model_class.class_eval do
        ernie_tag "Thingie"
      end
      i = @model_class.new
      assert_equal "Thingie", i.ernie_tag_name
    end

    should "be able to specify fields" do
      @model_class.class_eval do
        ernie_fields ["a", "b"]
      end
      i = @model_class.new(:a => "abc", :b => "xyz")
      expected = [
        {:name => "a", :value => "abc"},
        {:name => "b", :value => "xyz"}
      ]
      assert_equal expected, i.ernie_field_data
    end
    
    should "have no field data if no fields are specified" do
      i = @model_class.new(:a => "abc", :b => "xyz")
      assert_equal [], i.ernie_field_data
    end
  end
end
