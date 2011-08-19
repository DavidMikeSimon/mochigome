class StoreProduct < ActiveRecord::Base
  # A many-to-many-join model
  # Does not act as report focus

  belongs_to :store
  belongs_to :product
  has_many :sales

  validates_presence_of :store
  validates_presence_of :product
end
