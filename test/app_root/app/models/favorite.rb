class Favorite < ActiveRecord::Base
  acts_as_mochigome_focus

  belongs_to :owner
  belongs_to :product
end
