class Product < ActiveRecord::Base
  acts_as_mochigome_focus do |f|
    f.fields [:price]
    f.custom_subgroup_expression :name_ends_with_vowel,
      Mochigome::case_expr(
        Arel::Nodes::NamedFunction.new("SUBSTR", [Product.arel_table[:name], -1]).
          in(['a','e','i','o','u','A','E','I','O','U']),
        "Vowel",
        "Consonant"
      ).call(Product.arel_table)
  end
  has_mochigome_aggregations do |a|
    a.fields [
      :sum_price,
      {"Expensive products" => [
        :count,
        Mochigome::null_unless(
          lambda{|v| v.gt(10.00)},
          lambda{|t| t[:price]}
        )
      ]}
    ]
    a.hidden_fields [ {"Secret count" => [:count]} ]
    a.fields_in_ruby [ {"Count squared" => lambda{|row| row["Secret count"].try(:**, 2)}} ]
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
