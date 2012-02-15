class Category < ActiveRecord::Base
  acts_as_mochigome_focus

  has_many :products

  validates_presence_of :name
end
