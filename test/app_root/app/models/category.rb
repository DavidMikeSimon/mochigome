class Category < ActiveRecord::Base
  acts_as_report_focus do |f|
    f.fields [:name]
  end

  has_many :products

  validates_presence_of :name
end
