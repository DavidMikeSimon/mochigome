class Store < ActiveRecord::Base
  acts_as_mochigome_focus do |f|
    f.type_name "Storefront"
  end

  has_mochigome_aggregations do |a|
    a.fields [:count]
  end

  belongs_to :owner
  has_many :store_products
  has_many :products, :through => :store_products
  has_many :sales, :through => :store_products

  validates_presence_of :name
  validates_presence_of :owner
end
