module Mochigome
  module Formatting
    def self.percentify(n, d)
      ("%.1f%%" % ((n.to_f*100)/d.to_f)) if (!d.nil? && d > 0)
    end
  end
end
