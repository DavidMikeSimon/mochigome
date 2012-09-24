module Mochigome
  # An instance of SubgroupModel acts like a class that derives from
  # AR::Base, but is used to do subgrouping in Query and does not
  # interact with the database itself.
  class SubgroupModel
    attr_reader :model, :attr

    def initialize(model, attr)
      @model = model
      @attr = attr
      s = @model.mochigome_focus_settings
      if s && s.options[:custom_subgroup_exprs][attr]
        @attr_expr = s.options[:custom_subgroup_exprs][attr]
      elsif @model.columns_hash[@attr.to_s].try(:type) == :boolean
        @attr_expr = Mochigome::sql_bool_to_string(
          model.arel_table[@attr], "#{human_name.titleize}: "
        ).call(model.arel_table)
      else
        @attr_expr = nil
      end
      if @attr_expr && @attr_expr.respond_to?(:expr)
        @attr_expr = @attr_expr.expr
      end
      @focus_settings = Mochigome::ReportFocusSettings.new(@model)
      @focus_settings.type_name "#{@model.human_name} #{@attr.to_s.humanize}"
      @focus_settings.name lambda{|r| r.send(attr)}
    end

    def name
      # This works as both a valid SQL field name and a valid XML tag name
      "#{@model}__#{@attr}"
    end

    def human_name
      # Get rid of duplicate words (i.e. School$school_type)
      "#{@model.human_name} #{@attr.to_s.humanize}".split.map(&:downcase).uniq.join(" ")
    end

    def real_model?
      false
    end

    def to_real_model
      @model
    end

    def arel_table
      @model.arel_table
    end

    def primary_key
      @attr
    end

    def arel_primary_key
      if @attr_expr
        @attr_expr
      else
        arel_table[@attr]
      end
    end

    def connection
      @model.connection
    end

    def mochigome_focus_settings
      @focus_settings
    end

    def acts_as_mochigome_focus?
      true
    end

    def all(options = {})
      c = options[:conditions]
      unless c.is_a?(Hash) && c.size == 1 && c[@attr].is_a?(Array)
        raise QueryError.new("Invalid conditions given to SubgroupModel#all")
      end
      recs = c[@attr].compact.map do |val|
        SubgroupPseudoRecord.new(self, val)
      end
      # TODO: Support some kind of custom ordering
      recs.sort!{|a,b| a.value <=> b.value}
      recs
    end
  end

  private

  class SubgroupPseudoRecord
    attr_reader :subgroup_model, :value

    def initialize(subgroup_model, value)
      @subgroup_model = subgroup_model
      @value = value
    end

    def id
      @value
    end

    def mochigome_focus
      SubgroupPseudoRecordReportFocus.new(self)
    end
  end

  class SubgroupPseudoRecordReportFocus
    def initialize(rec)
      @rec = rec
    end

    def type_name
      @rec.subgroup_model.human_name
    end

    def name
      @rec.value
    end

    def field_data
      {}
    end
  end
end
