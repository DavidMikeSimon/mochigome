require 'factory_girl'
FactoryGirl.define do
  factory :product do
    name 'LG Optimus V'
    price 19.95
    category
  end

  factory :category do
    name 'Gadgets'
  end

  factory :store do
    name 'Best Buy'
    owner
  end

  factory :owner do
    first_name 'Thomas'
    last_name 'Edison'
    birth_date { 30.years.ago }
    phone_number "800-555-1212"
    email_address { "#{first_name}.#{last_name}@example.com".downcase }
  end
  
  factory :store_product do
    store
    product
  end

  factory :sale do
    store_product
  end
end
