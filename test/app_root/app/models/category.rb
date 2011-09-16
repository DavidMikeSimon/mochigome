class Category < ActiveRecord::Base
  acts_as_mochigome_focus do |f|
    f.fields [:name]
  end

  has_many :products

  validates_presence_of :name
end
