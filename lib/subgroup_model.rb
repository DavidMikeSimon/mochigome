module Mochigome
  # An instance of SubgroupModel acts like a class that derives from
  # AR::Base, but is used to do subgrouping in Query and does not
  # interact with the database itself.
  class SubgroupModel
    attr_reader :model, :attr

    def initialize(model, attr)
      @model = model
      @attr = attr
      @focus_settings = Mochigome::ReportFocusSettings.new(@model)
      @focus_settings.type_name "#{@model.human_name} #{@attr.to_s.humanize}"
      @focus_settings.name lambda{|r| r.send(attr)}
    end

    def name
      "#{@model}$#{@attr}" # Warning: This has to be a valid SQL field name
    end

    def human_name
      "#{@model.human_name} #{@attr.to_s.humanize}"
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
      arel_table[@attr]
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
