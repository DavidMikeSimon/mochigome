class CreateTables < ActiveRecord::Migration
  def self.up
    create_table :products do |t|
      t.string :name
      t.decimal :price
      t.integer :category_id
      t.timestamps
    end

    create_table :categories do |t|
      t.string :name
      t.timestamps
    end

    create_table :stores do |t|
      t.string :name
      t.integer :owner_id
      t.timestamps
    end

    create_table :owners do |t|
      t.string :first_name
      t.string :last_name
      t.date :birth_date
      t.string :phone_number
      t.string :email_address
      t.timestamps
    end

    create_table :store_products do |t|
      t.integer :store_id
      t.integer :product_id
    end

    create_table :sales do |t|
      t.integer :store_product_id
      t.timestamps
    end

    # Used by ModelExtensionTest to create temporary models
    create_table :fake do |t|
      t.timestamps
      t.string :a
      t.string :b
    end
  end
  
  def self.down
    drop_table :products
    drop_table :categories
    drop_table :stores
    drop_table :owners
    drop_table :store_products
    drop_table :sales
    drop_table :fake
  end
end
