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

      def has_mochigome_aggregations(aggregations)
        unless aggregations.respond_to?(:each)
          raise ModelSetupError.new "Call has_mochigome_aggregations with an Enumerable"
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
        mochigome_aggregations.concat(additions)
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
    attr_reader :group_name
    attr_reader :fields

    def initialize(owner, settings)
      @owner = owner
      @group_name = settings.options[:group_name] || owner.class.name
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

    def aggregate_data(assoc_name, options = {})
      h = ActiveSupport::OrderedHash.new
      assoc_name = assoc_name.to_sym
      if assoc_name == :all
        @owner.class.reflections.each do |name, assoc|
          h.merge! aggregate_data(name, options)
        end
      else
        assoc = @owner.class.reflections[assoc_name]
        assoc_object = @owner
        # TODO: Are there other ways context could matter besides :through assocs?
        # TODO: What if a through reflection goes through _another_ through reflection?
        if options.has_key?(:context) && assoc.through_reflection
          # FIXME: This seems like it's repeating Query work
          join_objs = assoc_object.send(assoc.through_reflection.name)
          options[:context].each do |obj|
            next unless join_objs.include?(obj)
            assoc = assoc.source_reflection
            assoc_object = obj
            break
          end
        end
        assoc.klass.mochigome_aggregations.each do |agg|
          # TODO: There *must* be a better way to do this query
          # It's ugly, involves an ActiveRecord creation, and causes lots of DB hits
          if assoc.belongs_to? # FIXME: or has_one
            obj = assoc_object.send(assoc.name)
            row = obj.class.find(obj.id, :select => "(#{agg[:expr]}) AS x")
          else
            row = assoc_object.send(assoc.name).first(:select => "(#{agg[:expr]}) AS x")
          end
          h["#{assoc_name}_#{agg[:name]}"] = row.x
        end
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
