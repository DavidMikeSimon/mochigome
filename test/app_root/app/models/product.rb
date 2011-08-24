class Product < ActiveRecord::Base
  acts_as_report_focus do |f|
    f.fields [:name, :price]
  end
  has_report_aggregations [:average_price]

  belongs_to :category
  has_many :store_products
  has_many :stores, :through => :store_products
  has_many :sales, :through => :store_products

  validates_presence_of :name
  validates_presence_of :price
  validates_numericality_of :price, :greater_than_or_equal_to => 0
  # Note: Does NOT validate presence of category!
  # We want to be able to find category-less products with a report.
end
