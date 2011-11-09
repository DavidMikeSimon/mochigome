module Mochigome
  @reportFocusModels = []
  def self.reportFocusModels
    @reportFocusModels
  end

  module ModelExtensions
    def self.included(base)
      base.extend(ClassMethods)

      base.write_inheritable_attribute :mochigome_focus_settings, nil
      base.class_inheritable_reader :mochigome_focus_settings

      base.write_inheritable_attribute :mochigome_aggregations, []
      base.class_inheritable_reader :mochigome_aggregations
    end

    module ClassMethods
      def acts_as_mochigome_focus
        if self.try(:mochigome_focus_settings).try(:orig_class) == self
          raise Mochigome::ModelSetupError.new("Already acts_as_mochigome_focus for #{self.name}")
        end
        settings = ReportFocusSettings.new(self)
        yield settings if block_given?
        write_inheritable_attribute :mochigome_focus_settings, settings
        send(:include, InstanceMethods)
        Mochigome::reportFocusModels << self
      end

      def acts_as_mochigome_focus?
        !!mochigome_focus_settings
      end

      AGGREGATION_FUNCS = {
        :count => lambda{|r| r[:id].count},
        :distinct => lambda{|r,c| r[c].count(true)},
        :average => lambda{|r,c| r[c].average},
        :avg => :average,
        :minimum => lambda{|r,c| r[c].minimum},
        :min => :minimum,
        :maximum => lambda{|r,c| r[c].maximum},
        :max => :maximum,
        :sum => lambda{|r,c| r[c].sum}
      }

      def has_mochigome_aggregations(aggregations)
        unless aggregations.is_a?(Enumerable)
          raise ModelSetupError.new "Call has_mochigome_aggregations with an Enumerable"
        end

        mochigome_aggregations.concat(aggregations.map {|f|
          case f
          when String, Symbol then
            {
              :name => "%s %s" % [name.pluralize, f.to_s.sub("_", " ")],
              :proc => aggregation_proc(f)
            }
          when Hash then
            {
              :name => f.keys.first.to_s,
              :proc => aggregation_proc(f.values.first)
            }
          else
            raise ModelSetupError.new "Invalid aggregation: #{f.inspect}"
          end
        })
      end

      private

      # Given an object, tries to coerce it into a proc that takes a relation
      # and returns an expression node to collect some data from that relation.
      def aggregation_proc(obj)
        return obj if obj.is_a?(Proc)
        args = if obj.is_a?(Symbol) || obj.is_a?(String)
          obj.to_s.split(/[ _]/).map(&:downcase).map(&:to_sym)
        elsif obj.is_a?(Enumerable)
          obj.clone # Going to enclose args, so we need it to stay unchanged
        else
          raise ModelSetupError.new "Invalid aggregation proc: #{obj.inspect}"
        end
        func_name = args.shift
        func = AGGREGATION_FUNCS[func_name]
        func = AGGREGATION_FUNCS[func] if func.is_a?(Symbol) # Alias lookup
        unless func
          raise ModelSetupError.new "Invalid function name: #{func_name}"
        end
        unless args.size == func.arity-1
          raise ModelSetupError.new "Wrong number of arguments for #{func_name}"
        end
        return lambda{|r| func.call(*([r] + args))} # Closure! Huzzah.
      end

      def assoc_to_rel(assoc_name)
      end
    end

    module InstanceMethods
      def mochigome_focus
        ReportFocus.new(self, self.class.mochigome_focus_settings)
      end
    end
  end

  private

  class ReportFocus
    attr_reader :name
    attr_reader :fields

    def initialize(owner, settings)
      @owner = owner
      @name = settings.options[:name] || owner.class.name
      @fields = settings.options[:fields] || []
    end

    def data(options = {})
      field_data.merge(aggregate_data(:all, options))
    end

    def field_data
      h = ActiveSupport::OrderedHash.new
      self.fields.each do |field|
        h[field[:name]] = field[:value_func].call(@owner)
      end
      h
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

    def name(n)
      unless n.is_a?(String)
        raise ModelSetupError.new "Call f.name with a String"
      end
      @options[:name] = n
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
