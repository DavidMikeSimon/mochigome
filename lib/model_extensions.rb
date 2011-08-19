module Ernie
  module ModelExtensions
    def self.included(base)
      base.extend(ClassMethods)

      base.write_inheritable_attribute :ernie_field_list, []
      base.class_inheritable_reader :ernie_field_list

      base.write_inheritable_attribute :ernie_tag_func, lambda {|obj| obj.class.name}
      base.class_inheritable_accessor :ernie_tag_func
    end

    module ClassMethods
      def ernie_fields(fields)
        fields.each do |f|
          case f
          when String, Symbol then ernie_field_list << {
            :name => f.to_s,
            :value_func => lambda{|obj| obj.send(f.to_sym)}
          }
          when Hash 
            ernie_field_list << {
              :name => f.keys.first.to_s,
              :value_func => (
                f.values.first.is_a?(Proc) ?
                f.values.first :
                lambda{|obj| obj.send(f.values.first.to_sym)}
              )
            }
          else raise "Invalid Ernie field #{f.inspect}"
          end
        end
      end

      def ernie_tag(str)
        self.ernie_tag_func = lambda{|x| str}
      end
    end

    def ernie_tag_name
      self.class.ernie_tag_func.call(self)
    end

    def ernie_field_data
      self.class.ernie_field_list.map do |field|
        {:name => field[:name], :value => field[:value_func].call(self)}
      end
    end
  end
end
