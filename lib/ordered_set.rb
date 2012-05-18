module Mochigome
  private

  # From http://stackoverflow.com/a/8451605/351149
   class OrderedSet < Set
    def initialize enum = nil, &block
      @hash = ActiveSupport::OrderedHash.new
      super
    end
  end
end
