class WidgetDivisor < ActiveRecord::Base
  acts_as_mochigome_focus do |f|
    f.name lambda {|r| "Divisor #{r.divisor}"}
    f.custom_association Widget, lambda {|src_tbl,tgt_tbl|
      # Argh, arel doesn't provide easy access to the modulus operator
      ((tgt_tbl[:number]/src_tbl[:divisor])*src_tbl[:divisor]).
        eq(tgt_tbl[:number])
    }
  end

  validates_presence_of :divisor
end
