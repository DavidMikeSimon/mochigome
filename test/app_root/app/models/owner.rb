class Owner < ActiveRecord::Base
  acts_as_mochigome_focus

  has_many :stores

  def name(reverse = false)
    if reverse
      "#{last_name}, #{first_name}"
    else
      "#{first_name} #{last_name}"
    end
  end

  def age
    ((Date.today - birth_date)/365.25).floor
  end
end
