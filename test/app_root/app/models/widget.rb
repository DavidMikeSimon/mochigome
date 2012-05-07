class Widget < ActiveRecord::Base
  acts_as_mochigome_focus do |f|
    f.name lambda {|r| "Widget #{r.number}"}
  end

  validates_presence_of :number
end
