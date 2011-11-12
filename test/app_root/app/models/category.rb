class Category < ActiveRecord::Base
  acts_as_mochigome_focus

  has_many :products, :conditions => {:categorized => true}

  validates_presence_of :name
end
