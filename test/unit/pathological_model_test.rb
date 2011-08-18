require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

# This is a unit test on the ability of model_extensions to correctly handle bad calls to Ernie methods 

class PathologicalModelTest < Test::Unit::TestCase
  agnostic_test "cannot specify ernie_tag_name multiple times" do
    assert_raise Offroad::ModelError do
      class MultipleTimesBrokenRecord < ActiveRecord::Base
        set_table_name "broken_records"
        acts_as_offroadable :global
        acts_as_offroadable :global
      end
    end
  end
end
