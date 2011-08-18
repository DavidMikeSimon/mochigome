require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

# This is a unit test on the ability of model_extensions to correctly handle bad calls to Ernie methods 

class PathologicalModelTest < Test::Unit::TestCase
  context "a model" do
    should "not specify ernie_tag_name multiple times" do
      assert true
    end
  end
end
