module Ernie
  @reportFocusModels = []
  def self.reportFocusModels
    @reportFocusModels
  end

  module ModelExtensions
    def self.included(base)
      base.extend(ClassMethods)
      base.write_inheritable_attribute :ernie_focus_settings, nil
      base.class_inheritable_reader :ernie_focus_settings
    end

    module ClassMethods
      def acts_as_report_focus
        if self.try(:ernie_focus_settings).try(:orig_class) == self
          raise Ernie::ModelSetupError.new("Already acts_as_report_focus for #{self.name}")
        end
        settings = ReportFocusSettings.new(self)
        yield settings if block_given?
        write_inheritable_attribute :ernie_focus_settings, settings
        send(:include, InstanceMethods)
        Ernie::reportFocusModels << self
      end

      def acts_as_report_focus?
        !!ernie_focus_settings
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
    attr_reader :orig_class

    def initialize(orig_class)
      @orig_class = orig_class
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
          :value_func => f.values.first.to_proc
        }
        else raise ModelSetupError.new "Invalid field: #{f.inspect}"
        end
      end
    end
  end
end
