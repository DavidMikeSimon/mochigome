require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

class ModelExtensionsTest < Test::Unit::TestCase
  context "a model" do
    setup do
      @model_class = Class.new(ActiveRecord::Base)
      @model_class.class_eval do
        set_table_name :unused
      end
    end
    
    should "have a default tag name the same as its class name" do
      SomeWeirdConstant = @model_class 
      i = SomeWeirdConstant.new
      assert_equal "SomeWeirdConstant", i.ernie_tag_name.split("::").last
      ModelExtensionsTest.send(:remove_const, :SomeWeirdConstant)
    end

    should "be able to override the default tag name" do
      @model_class.instance_eval do
        ernie_tag "Thingie"
      end
      i = @model_class.new
      assert_equal "Thingie", i.ernie_tag_name
    end
  end
end
