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

      base.write_inheritable_attribute :ernie_aggregations, []
      base.class_inheritable_reader :ernie_aggregations
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

      AGGREGATION_FUNCS = {
        'count' => 'count()',
        'distinct' => 'count(distinct %s)',
        'average' => 'avg(%s)',
        'avg' => 'avg(%s)',
        'minimum' => 'min(%s)',
        'min' => 'min(%s)',
        'maximum' => 'max(%s)',
        'max' => 'max(%s)',
        'sum' => 'sum(%s)'
      }

      def has_report_aggregations(aggregations)
        unless aggregations.respond_to?(:each)
          raise ModelSetupError.new "Call has_report_aggregations with an Enumerable"
        end

        def aggregation_expr(obj)
          if obj.is_a?(String)
            AGGREGATION_FUNCS.each do |func, expr_pat|
              if expr_pat.include?('%s')
                if obj =~ /^#{func}[-_ ](.+)/i
                  return (expr_pat % $1)
                end
              else
                if obj.downcase == func
                  return expr_pat
                end
              end
            end
          end
          raise ModelSetupError.new "Invalid aggregation expr: #{obj.inspect}"
        end

        additions = aggregations.map do |f|
          case f
          when String, Symbol then {
            :name => f.to_s,
            :expr => aggregation_expr(f.to_s)
          }
          else raise ModelSetupError.new "Invalid aggregation: #{f.inspect}"
          end
        end
        ernie_aggregations.concat(additions)
      end

      def has_report_aggregations?
        ernie_aggregations.size > 0
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
      # TODO: Use an ordered hash here
      self.fields.map do |field|
        {:name => field[:name], :value => field[:value_func].call(@owner)}
      end
    end

    def aggregate_data(assoc_name)
      # TODO: Use an ordered hash here
      assoc_name = assoc_name.to_sym
      if assoc_name == :all
        @owner.class.reflections.map{|name, assoc| aggregate_data(name)}.compact.flatten(1)
      else
        # TODO: Check if association actually available
        @owner.class.reflections[assoc_name].klass.ernie_aggregations.map do |agg|
          {
            :name => "#{assoc_name}_#{agg[:name]}",
            # FIXME: Is there a way to do below without creating a fake instance of assoc.klass?
            :value => @owner.send(assoc_name).all(
              :select => "(#{agg[:expr]}) AS erniecalc"
            ).first.erniecalc
          }
        end
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
