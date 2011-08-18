class StoreProduct < ActiveRecord::Base
  # join model
  belongs_to :store
  belongs_to :product
  has_many :sales

  validates_presence_of :store
  validates_presence_of :product
end
