module Ernie
  class Aggregator
    attr_accessor :focus

    def initialize(layers)
      @layers = layers
      @focus = nil
    end
    
    def run
      dataset = DataSet.new(@layers)
      dataset
    end
  end
end
