class WidgetDivisor < ActiveRecord::Base
  acts_as_mochigome_focus do |f|
    f.name lambda {|r| "Divisor #{r.divisor}"}
    f.custom_association Widget, lambda {|src_tbl,tgt_tbl|
      # Argh, arel doesn't provide easy access to the modulus operator
      (src_tbl[:divisor]*Arel::Nodes::NamedFunction.new(
        "ROUND",
        [(tgt_tbl[:number]/src_tbl[:divisor]) - 0.5]
      )).eq(tgt_tbl[:number])
    }
  end

  validates_presence_of :divisor
end
