# FIXME This whole controller needs a major cleanup, should really
# be largely moved into some base class in Mochigome.

class ReportController < ApplicationController
  FOCUS_MODELS = {}
  HUMAN_FOCUS_MODELS = {}
  [
    Owner,
    Store,
    Product,
    Category
  ].each do |m|
    FOCUS_MODELS[m.name] = m
    HUMAN_FOCUS_MODELS[m.human_name.titleize] = m.name
  end

  AGGREGATE_SOURCES = [
    ["Staff Attendance", "User:AttendanceRecord"],
    ["Staff Count", "User"],
    ["School Count", "School"],
    ["Student Attendance", "Student:AttendanceRecord"],
    ["Student Count", "Student"]
  ]

  def show
    return redirect_to(:action => :edit) if params.size <= 2
    begin
      query = setup_query
      data_node = run_report(query)
      generate_charts(data_node)
      output_report(data_node)
    rescue Mochigome::QueryError => e
      flash[:alert] = "Sorry, these report settings are not valid: #{e.message}"
      return redirect_to(params.merge(:action => :edit))
    end
  end

  def edit
    @possible_layer_models = HUMAN_FOCUS_MODELS.map{|k, v| [k, v]}.sort
  end

  private

  def condition_desc(c)
    cls = c['cls'].strip.constantize
    cls_name = cls.human_name.titleize

    ref_cls = nil
    if c['fld'] == cls.primary_key
      ref_cls = cls
    else
      cls.reflections.map(&:last).select{|r| r.belongs_to?}.each do |r|
        if r.association_foreign_key == c['fld']
          ref_cls = r.klass
          break
        end
      end
    end

    if ref_cls && c['op'] == 'eq'
      item = ref_cls.find(c['val'].to_i)
      ref_name = cls_name + (cls == ref_cls ? "" : " - #{ref_cls.human_name}")
      return "#{ref_name}: #{item.display_s}"
    else
      return [
        cls_name,
        c['fld'].humanize.downcase.gsub(cls_name.downcase, ''),
        arel_op_humanize(c['op']),
        c['val'].to_s
      ].join(" ")
    end
  end

  def arel_op_humanize(op)
    op.
      gsub('gteq', 'greater than or equal to').
      gsub('lteq', 'less than or equal to').
      gsub('eq', 'equal to').
      gsub('lt', 'less than').
      gsub('gt', 'greater than').
      humanize.downcase
  end

  helper_method :condition_desc, :arel_op_humanize

  def setup_query
    raise Mochigome::QueryError.new("No layers provided") if @layer_names.empty?
    layers = @layer_names.map{|n| FOCUS_MODELS[n]}

    aggregate_sources = @aggregate_source_names.map do |s|
      # Each aggregate source is a focus type paired with a data type
      r = s.split(":").map(&:strip).map(&:constantize)
      r.size > 1 ? r : r.first
    end

    @report_name = "#{layers.last.human_name.pluralize.titleize} Report"
    unless @aggregate_source_names.empty?
      @report_name += " : " + @aggregate_source_names.map{|n|
        n.gsub(":","").underscore.titleize.pluralize
      }.join(", ")
    end

    Mochigome::Query.new(layers,
      :aggregate_sources => aggregate_sources,
      #:access_filter => cancan_access_filter_proc,
      :root_name => @report_name
    )
  end

  def run_report(query)
    full_cond = nil
    @condition_params.each do |c|
      cls = c['cls'].strip.constantize # TODO : Verify it's AR::Base
      # TODO: Join cls into the query if it's not already (join on what, though?)
      raise "No such op #{c['op']}" unless Arel::Predications.instance_methods.include?(c['op'])
      val = interpret_val(cls, c['fld'], c['val'])
      cond = Arel::Table.new(cls.table_name)[c['fld']].send(c['op'], val)
      full_cond = full_cond ? full_cond.and(cond) : cond
    end
    query.run(full_cond)
  end

  def interpret_val(cls, fld, val)
    if val.is_a?(Array)
      val.map{|v| interpret_val(cls, fld, v)}
    else
      val = val.to_s
      column = cls.columns_hash[fld] or raise "Can't find column #{fld} in #{cls}"
      begin
        case column.type
          when :boolean then (val.to_i != 0)
          when :date then Date.parse(val)
          when :datetime then DateTime.parse(val)
          when :time then Time.parse(val) # FIXME: Time#parse silently defaults to cur time!
          when :integer then val.to_i
          when :string, :text then val
          else raise "Unknown column type #{column.type} for #{fld} in #{cls}"
        end
      rescue ArgumentError
        raise Mochigome::QueryError.new("Unable to interpret value: #{val}")
      end
    end
  end

  def generate_charts(data_node)
    @charts = []
    return if data_node.children.size > 15 || data_node.children.empty?

    @aggregate_source_names.each do |raw_name|
      agg = AGGREGATE_SOURCES.select{|s| s[1] == raw_name}.first
      next unless agg

      chart_options = {
        :type => 'bar',
        :title => agg[0],
        # :title_size => 20, # FIXME: Argh, googlecharts gem isn't reliable
        :size => '720x250',
        :bg => 'FFFFFF00', # White with fully-transparent alpha
        :stacked => false,
        :bar_colors => '859900,b58900,dc322f,268bd2',
        :axis_with_labels => 'x,y',
        :class => 'chart',
        :alt => agg[0] + " Chart",
        :custom => "chdlp=b|l"
      }

      data_model = agg[1].split(":").last.constantize
      agg_fields = data_model.mochigome_aggregation_settings.options[:fields].
        reject{|f| f[:hidden]}

      # TODO: If there's only one agg field, we can use series names
      # to go another level down in the report instead.
      chart_options[:legend] = agg_fields.map{|f| f[:name]}
      chart_options[:data] = agg_fields.map do |f|
        data_node.children.map do |n|
          (n[f[:name]] || "").to_f
        end
      end
      chart_options[:axis_labels] = [data_node.children.map{|n| n.name}]
      x_gap = [450/(chart_options[:axis_labels][0].size), 70].min
      chart_options[:bar_width_and_spacing] = [8,2,x_gap]

      min_val = [0, chart_options[:data].flatten.min].min
      max_val = [100, chart_options[:data].flatten.max].max
      chart_options[:axis_range] = [nil, [min_val, max_val]]
      chart_options[:min_value] = chart_options[:axis_range][1][0]
      chart_options[:max_value] = chart_options[:axis_range][1][1]

      if chart_options[:axis_labels][0].size > 7
        chart_options[:axis_labels][0].reverse!
        chart_options[:orientation] = 'horizontal'
        chart_options[:class] += ' horizontal'
        chart_options[:axis_with_labels] = 'y,x'
        chart_options[:size] = "350x#{chart_options[:axis_labels][0].size*65}"
        chart_options[:bar_width_and_spacing][2] = 10
      end

      @charts << Gchart.new(chart_options).image_tag
    end
  end

  def output_report(data_node)
    # These instance variables are used by the HTML transform
    # FIXME: Just do the non-data part of the sidebar in HAML instead
    # To do that, use seperate transforms for sidebar links and main content
    @print_path = report_path(params.merge(:format => "pdf", :auto_print => true))
    @download_paths = []
    [
      [:pdf, "PDF Document"],
      [:xlsx, "Excel 2007 Spreadsheet"],
      [:csv, "CSV Spreadsheet"],
      [:xml, "XML Raw Data"]
    ].each do |ext, name|
      @download_paths << {
        :path => report_path(params.merge(
          :format => ext,
          :auto_print => false,
          :download => true
        )),
        :name => name,
        :ext => ext
      }
    end

    transform_opts = {
      :src_type => "report",
      :context => self
    }

    filename = "report"
    respond_to do |format|
      format.html do
        @report_html = Morpheus.transform(
          data_node.to_xml,
          transform_opts.merge(:tgt_format => "html")
        ).to_html.html_safe
        render
      end
      format.xlsx do
        send_xlsx(data_node.to_flat_arrays, "#{filename}.xlsx")
      end
      format.csv do
        send_csv(data_node.to_flat_arrays, "#{filename}.csv")
      end
      format.pdf do
        fo_data = Morpheus.transform(
          data_node.to_xml,
          transform_opts.merge(:tgt_format => "fo")
        )
        send_pdf(fo_data, "#{filename}.pdf", params[:download],
          :from_url => report_url(params.merge(:format => "html")),
          :auto_print => !params[:download]
        )
      end
      format.xml do
        send_data(
          data_node.to_xml.to_s,
          :type => "application/xml",
          :disposition => 'attachment',
          :filename => "#{filename}.xml"
        )
      end
    end
  end

  # If you're using CanCan, this access filter will restrict your report
  # results by the current user's permissions.
  def cancan_access_filter_proc
    af = proc do |cls|
      r = {}
      return r unless cls.real_model?
      rules = current_ability.send(:relevant_rules_for_query, :index, cls)
      return r if rules.empty?
      adapter = CanCan::ModelAdapters::ActiveRecordAdapter.new(cls, rules)
      conditions = adapter.conditions
      conditions = cls.send(:sanitize_sql, conditions) if conditions.is_a?(Hash)
      conditions = nil if conditions == "1=1"
      if conditions
        r[:condition] =
          (Arel::Table.new(cls.table_name)[cls.primary_key].eq(nil)).or(
            Arel::Nodes::SqlLiteral.new("(#{conditions})"))
      end
      if adapter.joins
        r[:join_paths] = pathify_cancan_joins(adapter.joins).map{|p| [cls] + p}
      end
      r
    end
  end

  def pathify_cancan_joins(j)
    case j
      when Array then
        j.map{|i| pathify_cancan_joins(i)}
      when Hash then
        j.map{|k,v| pathify_cancan_joins(k) + pathify_cancan_joins(v).flatten}.flatten
      when Symbol then
        [j.to_s.classify.constantize]
      else raise "Invalid cancan join path element #{j.inspect}"
    end
  end

  # FIXME: Factor the send_X methods below

  def send_pdf(fo_data, filename, download, pdf_options = {})
    pdf = ApacheFop::generate_pdf(fo_data, pdf_options)
    begin
      send_file(
        pdf.path,
        :stream => false, # If this was on, temp file would be deleted too early
        :type => "application/pdf",
        :filename => filename,
        :disposition => download ? 'attachment' : 'inline'
      )
    ensure
      # FIXME: To allow use of X-Send-File, use a separate cron task to delete
      # stale pdf files periodically.
      pdf.close!
    end
  end

  def send_xlsx(table, filename)
    file = Tempfile.new("excel")
    begin
      path = file.path
      file.close!
      SimpleXlsx::Serializer.new(path) do |bk|
        bk.add_sheet("Report") do |sheet|
          table.each do |row|
            sheet.add_row row
          end
        end
      end
      send_file(
        path,
        :stream => false, # If this was on, temp file would be deleted too early
        :type => Mime::XLSX,
        :filename => filename,
        :disposition => 'attachment'
      )
    ensure
      # FIXME: To allow use of X-Send-File, use a separate cron task to delete
      # stale files periodically.
      File.unlink(path) if File.exists?(path)
    end
  end

  def send_csv(table, filename)
    file = Tempfile.new("csv")
    begin
      path = file.path
      file.close!
      FasterCSV.open(path, "w") do |csv|
        table.each do |row|
          csv << row
        end
      end
      send_file(
        path,
        :stream => false, # If this was on, temp file would be deleted too early
        :type => Mime::CSV,
        :filename => filename,
        :disposition => 'attachment'
      )
    ensure
      # FIXME: To allow use of X-Send-File, use a separate cron task to delete
      # stale files periodically.
      File.unlink(path) if File.exists?(path)
    end
  end


  before_filter :load_params
  def load_params
    @layer_names = []
    if params[:l].is_a?(Array)
      @layer_names = params[:l].reject(&:blank?).map(&:strip)
    end

    @condition_params = []
    if params[:c].is_a?(Hash)
      @condition_params = params[:c].values.reject(&:blank?)
    end
    @condition_descs = @condition_params.map{|c| condition_desc(c)}

    @aggregate_source_names = []
    if params[:a].is_a?(Array)
      @aggregate_source_names = params[:a].reject(&:blank?)
    end
  end
end
