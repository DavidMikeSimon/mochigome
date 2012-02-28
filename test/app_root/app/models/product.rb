class Product < ActiveRecord::Base
  acts_as_mochigome_focus do |f|
    f.fields [:price]
  end
  has_mochigome_aggregations do |a|
    a.fields [
      :sum_price,
      {"Expensive products" => [:count_predicate, :price,
        lambda{|price| price.gt(10.00)}
      ]}
    ]
    a.hidden_fields [ {"Secret count" => :count} ]
    a.fields_in_ruby [ {"Count squared" => lambda{|row| row["Secret count"]**2}} ]
  end

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
