module Mochigome
  module ModelExtensions
    def self.included(base)
      base.extend(ClassMethods)

      base.write_inheritable_attribute :mochigome_focus_settings, nil
      base.class_inheritable_reader :mochigome_focus_settings

      # TODO: Use an ordered hash for this
      base.write_inheritable_attribute :mochigome_aggregation_settings, nil
      base.class_inheritable_reader :mochigome_aggregation_settings
    end

    module ClassMethods
      def real_model?
        true
      end

      def to_real_model
        self
      end

      # TODO: Use this instead of calling Table.new all over the place
      def arel_table
        Arel::Table.new(table_name)
      end

      def arel_primary_key
        arel_table[primary_key]
      end

      def acts_as_mochigome_focus
        if self.try(:mochigome_focus_settings).try(:model) == self
          raise Mochigome::ModelSetupError.new("Already acts_as_mochigome_focus for #{self.name}")
        end
        settings = ReportFocusSettings.new(self)
        yield settings if block_given?
        write_inheritable_attribute :mochigome_focus_settings, settings
        send(:include, InstanceMethods)
      end

      def acts_as_mochigome_focus?
        !!mochigome_focus_settings
      end

      # TODO: Split out aggregation stuff into its own module

      def has_mochigome_aggregations
        if self.try(:mochigome_aggregation_settings).try(:model) == self
          raise Mochigome::ModelSetupError.new("Already aggregation settings for #{self.name}")
        end
        settings = AggregationSettings.new(self)
        yield settings if block_given?
        write_inheritable_attribute :mochigome_aggregation_settings, settings
      end

      def arelified_assoc(name)
        # TODO: Deal with polymorphic assocs.
        model = self
        assoc = reflect_on_association(name)
        raise AssociationError.new("No such assoc #{name}") unless assoc
        table = Arel::Table.new(table_name)
        ftable = Arel::Table.new(assoc.klass.table_name)
        lambda do |r|
          # FIXME: This acts as though arel methods are non-destructive,
          # but they are, right? Except, I can't remove the rel
          # assignment from relation_over_path...
          cond = nil
          if assoc.belongs_to?
            cond = table[assoc.association_foreign_key].eq(
              ftable[assoc.klass.primary_key]
            )
          else
            cond = table[primary_key].eq(ftable[assoc.primary_key_name])
          end

          if assoc.options[:as]
            # FIXME Can we assume that this is the polymorphic type field?
            cond = cond.and(ftable["#{assoc.options[:as]}_type"].eq(model.name))
          end

          # TODO: Apply association conditions.

          r.join(ftable, Arel::Nodes::InnerJoin).on(cond)
        end
      end

    end

    module InstanceMethods
      def mochigome_focus
        ReportFocus.new(self, self.class.mochigome_focus_settings)
      end
    end
  end

  # FIXME This probably doesn't belong here. Maybe I should have a module
  # for this kind of stuff and also put the standard aggregation functions
  # in there?

  def self.null_unless(pred, value_func)
    lambda {|t|
      value = value_func.call(t)
      val_expr = Arel::Nodes::NamedFunction.new('',[value])
      Arel::Nodes::SqlLiteral.new(
        "(CASE WHEN #{pred.call(value).to_sql} THEN #{val_expr.to_sql} ELSE NULL END)"
      )
    }
  end

  private

  class ReportFocus
    attr_reader :type_name
    attr_reader :fields

    def initialize(owner, settings)
      @owner = owner
      @name_proc = settings.options[:name] || lambda{|obj| obj.name}
      @type_name = settings.options[:type_name] || owner.class.human_name
      @fields = settings.options[:fields] || []
    end

    def name
      @name_proc.call(@owner)
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
    attr_reader :model
    attr_reader :ordering

    def initialize(model)
      @model = model
      @options = {}
      @options[:fields] = []
    end

    def type_name(n)
      unless n.is_a?(String)
        raise ModelSetupError.new "Call f.type_name with a String"
      end
      @options[:type_name] = n
    end

    def name(n)
      @options[:name] = n.to_proc
    end

    def ordering(n)
      @options[:ordering] = n.to_s
    end

    def get_ordering
      @options[:ordering] || @model.primary_key.to_s
    end

    def fields(fields)
      unless fields.respond_to?(:each)
        raise ModelSetupError.new "Call f.fields with an Enumerable"
      end

      @options[:fields] += fields.map do |f|
        case f
        when String, Symbol then {
          :name => Mochigome::complain_if_reserved_name(f.to_s.strip),
          :value_func => lambda{|obj| obj.send(f.to_sym)}
        }
        when Hash then {
          :name => Mochigome::complain_if_reserved_name(f.keys.first.to_s.strip),
          :value_func => f.values.first.to_proc
        }
        else raise ModelSetupError.new "Invalid field: #{f.inspect}"
        end
      end
    end
  end

  class AggregationSettings
    attr_reader :options
    attr_reader :model

    def initialize(model)
      @model = model
      @options = {}
      @options[:fields] = []
    end

    def fields(aggs)
      unless aggs.is_a?(Enumerable)
        raise ModelSetupError.new "Call a.fields with an Enumerable"
      end

      @options[:fields].concat(aggs.map {|f|
        case f
        when String, Symbol then
          {
            :name => "%s %s" % [@model.name.pluralize, f.to_s.sub("_", " ")]
          }.merge(Mochigome::split_out_aggregation_procs(f))
        when Hash then
          if f.size == 1
            {
              :name => f.keys.first.to_s
            }.merge(Mochigome::split_out_aggregation_procs(f.values.first))
          else
            {
              :name => f[:name],
              :value_proc => Mochigome::value_proc(f[:value]),
              :agg_proc => Mochigome::aggregation_proc(f[:aggregation])
            }
          end
        else
          raise ModelSetupError.new "Invalid aggregation: #{f.inspect}"
        end
      })
    end

    def hidden_fields(aggs)
      orig_keys = Set.new @options[:fields].map{|a| a[:name]}
      fields(aggs)
      @options[:fields].each do |h|
        next if orig_keys.include? h[:name]
        h[:hidden] = true
      end
    end

    def fields_in_ruby(aggs)
      @options[:fields].concat(aggs.map {|f|
        raise ModelSetupError.new "Invalid ruby agg #{f.inspect}" unless f.is_a?(Hash)
        {
          :name => f.keys.first.to_s,
          :ruby_proc => f.values.first,
          :in_ruby => true
        }
      })
    end
  end

  def self.complain_if_reserved_name(s)
    test_s = s.gsub(/ +/, "_").underscore
    ['name', 'id', 'type', 'internal_type'].each do |reserved|
      if test_s == reserved
        raise ModelSetupError.new "Field name \"#{s}\" conflicts with reserved term \"#{reserved}\""
      end
    end
    s
  end

  AGGREGATION_FUNCS = {
    :count => lambda{|a| a.count},
    :distinct => lambda{|a| a.count(true)},
    :average => lambda{|a| a.average},
    :avg => :average,
    :minimum => lambda{|a| a.minimum},
    :min => :minimum,
    :maximum => lambda{|a| a.maximum},
    :max => :maximum,
    :sum => lambda{|a| a.sum}
  }

  # Given an object, tries to coerce it into a proc that takes a node
  # and returns an expression node to collect some aggregate data from it.
  def self.aggregation_proc(obj)
    if obj.is_a?(Symbol)
      orig_name = obj
      2.times do
        # Lookup twice to allow for indirect aliases in AGGREGATION_FUNCS
        obj = AGGREGATION_FUNCS[obj] if obj.is_a?(Symbol)
      end
      raise ModelSetupError.new "Can't find aggregation function #{orig_name}" unless obj
      obj
    elsif obj.is_a?(Proc)
      obj
    else
      raise ModelSetupError.new "Invalid aggregation function #{obj.inspect}"
    end
  end

  # Given an object, tries to coerce it into a proc that takes a relation
  # and returns a node for some value in it to be aggregated over
  def self.value_proc(obj)
    if obj.is_a?(Symbol)
      lambda {|t| t[obj]}
    elsif obj.is_a?(Proc)
      obj
    else
      raise ModelSetupError.new "Invalid value function #{obj.inspect}"
    end
  end

  def self.split_out_aggregation_procs(obj)
    case obj
    when Symbol, String
      vals = obj.to_s.split(/[ _]/).map(&:downcase).map(&:to_sym)
    when Array
      vals = obj.dup
    else
      raise ModelSetupError.new "Invalid aggregation type: #{obj.inspect}"
    end

    if vals.size == 1
      vals << :id # TODO : Use real primary key, only do this for appropriate agg funcs
    elsif vals.empty? || vals.size > 3
      raise ModelSetupError.new "Wrong # of components for agg: #{obj.inspect}"
    end

    {
      :agg_proc => aggregation_proc(vals[0]),
      :value_proc => value_proc(vals[1])
    }.merge(vals[2] || {})
  end
end
