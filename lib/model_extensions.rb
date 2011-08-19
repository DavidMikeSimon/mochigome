module Ernie
  module ModelExtensions
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def acts_as_report_focus
        settings = ReportFocusSettings.new
        yield settings if block_given?
        write_inheritable_attribute :ernie_focus_settings, settings
        class_inheritable_reader :ernie_focus_settings
        send(:include, InstanceMethods)
      end
    end

    module InstanceMethods
      def report_focus
        ReportFocus.new(self, self.class.ernie_focus_settings)
      end
    end
  end

  private

  class ReportFocus
    attr_reader :group_name
    attr_reader :fields

    def initialize(owner, settings)
      @owner = owner
      @group_name = settings.options[:group_name] || owner.class.name
      @fields = settings.options[:fields] || []
    end

    def data
      self.fields.map do |field|
        {:name => field[:name], :value => field[:value_func].call(@owner)}
      end
    end
  end

  class ReportFocusSettings
    attr_reader :options

    def initialize
      @options = {}
      @options[:fields] = []
    end

    def group_name(n)
      unless n.is_a?(String)
        raise ModelSetupError.new "Call f.group_name with a String"
      end
      @options[:group_name] = n
    end

    def fields(fields)
      unless fields.respond_to?(:each)
        raise ModelSetupError.new "Call f.fields with an Enumerable"
      end
      @options[:fields] += fields.map do |f|
        case f
        when String, Symbol then {
          :name => f.to_s,
          :value_func => lambda{|obj| obj.send(f.to_sym)}
        }
        when Hash then {
          :name => f.keys.first.to_s,
          :value_func => (
            f.values.first.is_a?(Proc) ?
            f.values.first : lambda{|obj| obj.send(f.values.first.to_sym)}
          )
        }
        else raise ModelSetupError.new "Invalid field: #{f.inspect}"
        end
      end
    end
  end
end
