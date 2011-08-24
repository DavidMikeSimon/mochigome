class Sale < ActiveRecord::Base
  acts_as_report_focus
  has_report_aggregations [:count]
  
  belongs_to :store_product
  has_one :store, :through => :store_product
  has_one :product, :through => :store_product

  validates_presence_of :store_product
end
