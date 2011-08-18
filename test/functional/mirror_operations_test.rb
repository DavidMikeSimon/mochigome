require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

class MirrorOperationsTest < ActionController::TestCase
  tests GroupController
  
  cross_test "can create an offline app then use it to work with the online app" do
    mirror_data = ""
    in_online_app do
      Group.create(:name => "Some Other Group")
      Group.create(:name => "Some Other Offline Group").group_offline = true
      test_group = Group.create(:name => "Test Group")
      
      grec_a = GlobalRecord.create(:title => "Important Announcement", :some_boolean => true)
      GlobalRecord.create(:title => "Trivial Announcement", :some_boolean => true, :friend => grec_a)
      
      GroupOwnedRecord.create(:description => "First Item", :group => test_group)
      GroupOwnedRecord.create(:description => "Second Item", :group => test_group)
      third = GroupOwnedRecord.create(:description => "Third Item", :group => test_group)
      SubRecord.create(:description => "Subitem A", :group_owned_record => third)
      SubRecord.create(:description => "Subitem B", :group_owned_record => third)
      
      test_group.favorite = GroupOwnedRecord.find_by_description("Third Item")
      test_group.save

      test_group.group_offline = true
      get :download_initial_down_mirror, "id" => test_group.id
      mirror_data = @response.binary_content
    end
    
    in_offline_app(false, true) do
      assert_equal 0, Group.count
      assert_equal 0, GlobalRecord.count
      assert_equal 0, GroupOwnedRecord.count
      
      post :upload_initial_down_mirror, "mirror_data" => mirror_data
      
      assert_equal 1, Group.count
      test_group = Group.find_by_name("Test Group")
      assert_not_nil test_group
      
      assert_equal 3, GroupOwnedRecord.count
      assert_not_nil GroupOwnedRecord.find_by_description("First Item")
      assert_not_nil GroupOwnedRecord.find_by_description("Second Item")
      assert_not_nil GroupOwnedRecord.find_by_description("Third Item")
      assert_not_nil SubRecord.find_by_description("Subitem A")
      assert_not_nil SubRecord.find_by_description("Subitem B")
      
      assert_equal GroupOwnedRecord.find_by_description("Third Item"), test_group.favorite
      assert_equal GroupOwnedRecord.find_by_description("Third Item"), SubRecord.find_by_description("Subitem A").group_owned_record
      assert_equal GroupOwnedRecord.find_by_description("Third Item"), SubRecord.find_by_description("Subitem B").group_owned_record
      
      assert_equal 2, GlobalRecord.count
      grec_a = GlobalRecord.find_by_title("Important Announcement")
      grec_b = GlobalRecord.find_by_title("Trivial Announcement")
      assert_not_nil grec_a
      assert_not_nil grec_b
      assert_equal grec_a, grec_b.friend
      
      group = Group.first
      group.name = "Renamed Group"
      group.save!
      
      first_item = GroupOwnedRecord.find_by_description("First Item")
      first_item.description = "Absolutely The First Item"
      first_item.save!
      
      second_item = GroupOwnedRecord.find_by_description("Second Item")
      second_item.destroy

      subitem_a = SubRecord.find_by_description("Subitem A")
      subitem_a.description = "Subitem Apple"
      subitem_a.save!

      subitem_b = SubRecord.find_by_description("Subitem B")
      subitem_b.destroy
      
      get :download_up_mirror, "id" => group.id
      mirror_data = @response.binary_content
    end
    
    in_online_app do
      GlobalRecord.find_by_title("Trivial Announcement").destroy
      GlobalRecord.create(:title => "Yet Another Announcement")
      rec = GlobalRecord.find_by_title("Important Announcement")
      rec.title = "Very Important Announcement"
      rec.save

      assert_equal 3, Group.find_by_name("Test Group").group_owned_records.size

      post :upload_up_mirror, "id" => Group.find_by_name("Test Group").id, "mirror_data" => mirror_data
      
      assert_nil Group.find_by_name("Test Group")
      assert_not_nil Group.find_by_name("Renamed Group")
      
      assert_equal 2, Group.find_by_name("Renamed Group").group_owned_records.size
      assert_nil GroupOwnedRecord.find_by_description("First Item")
      assert_not_nil GroupOwnedRecord.find_by_description("Absolutely The First Item")
      assert_nil GroupOwnedRecord.find_by_description("Second Item")
      assert_not_nil GroupOwnedRecord.find_by_description("Third Item")
      assert_nil SubRecord.find_by_description("Subitem A")
      assert_not_nil SubRecord.find_by_description("Subitem Apple")
      assert_nil SubRecord.find_by_description("Subitem B")
      
      get :download_down_mirror, "id" => Group.find_by_name("Renamed Group").id
      mirror_data = @response.binary_content
    end
    
    in_offline_app do
      post :upload_down_mirror, "id" => Group.first.id, "mirror_data" => mirror_data
      
      assert_equal 2, GlobalRecord.count
      assert_nil GlobalRecord.find_by_title("Important Announcement")
      assert_not_nil GlobalRecord.find_by_title("Very Important Announcement")
      assert_nil GlobalRecord.find_by_title("Trivial Announcement")
      assert_not_nil GlobalRecord.find_by_title("Yet Another Announcement")
      
      group = Group.first
      first_item = GroupOwnedRecord.find_by_description("Absolutely The First Item")
      third_item = GroupOwnedRecord.find_by_description("Third Item")
      group.favorite = first_item
      group.save
      first_item.parent = third_item
      first_item.save
      third_item.parent = third_item
      third_item.save
      
      subitem = SubRecord.find_by_description("Subitem Apple")
      subitem.group_owned_record = first_item
      subitem.save
      
      get :download_up_mirror, "id" => Group.first.id
      mirror_data = @response.binary_content
    end
    
    in_online_app do
      post :upload_up_mirror, "id" => Group.find_by_name("Renamed Group").id, "mirror_data" => mirror_data
      
      group = Group.find_by_name("Renamed Group")
      first_item = GroupOwnedRecord.find_by_description("Absolutely The First Item")
      third_item = GroupOwnedRecord.find_by_description("Third Item")
      subrec = SubRecord.find_by_description("Subitem Apple")
      assert_equal first_item, group.favorite
      assert_equal third_item, first_item.parent
      assert_equal third_item, third_item.parent
      assert_equal first_item, subrec.group_owned_record
    end
  end
end
