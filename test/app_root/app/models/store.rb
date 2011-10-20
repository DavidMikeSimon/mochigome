class Store < ActiveRecord::Base
  acts_as_mochigome_focus do |f|
    f.fields [:name]
    f.name "Storefront"
  end

  belongs_to :owner
  has_many :store_products
  has_many :products, :through => :store_products
  has_many :sales, :through => :store_products

  validates_presence_of :name
  validates_presence_of :owner
end
