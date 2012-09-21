require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

describe "an ActiveRecord model" do
  before do
    @model_class = Class.new(ActiveRecord::Base)
    @model_class.class_eval do
      set_table_name :fake
      def name
        "Moby"
      end
      def last_name
        "Dick"
      end
    end
    Whale = @model_class
  end

  after do
    Object.send(:remove_const, :Whale)
  end

  it "indicates if it acts_as_mochigome_focus or not" do
    refute @model_class.acts_as_mochigome_focus?
    @model_class.class_eval do
      acts_as_mochigome_focus
    end
    assert @model_class.acts_as_mochigome_focus?
  end

  it "cannot call acts_as_mochigome_focus more than once" do
    @model_class.class_eval do
      acts_as_mochigome_focus
    end
    assert_raises Mochigome::ModelSetupError do
      @model_class.class_eval do
        acts_as_mochigome_focus
      end
    end
  end

  it "inherits a parent's report focus settings" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.type_name "Foobar"
      end
    end
    @sub_class = Class.new(@model_class)
    i = @sub_class.new
    assert_equal "Foobar", i.mochigome_focus.type_name
  end

  it "can override a parent's report focus settings" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.type_name "Foobar"
      end
    end
    @sub_class = Class.new(@model_class)
    @sub_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.type_name "Narfbork"
      end
    end
    i = @sub_class.new
    assert_equal "Narfbork", i.mochigome_focus.type_name
  end

  it "uses its class name as the default type name" do
    @model_class.class_eval do
      acts_as_mochigome_focus
    end
    i = @model_class.new
    assert_equal "Whale", i.mochigome_focus.type_name.split("::").last
  end

  it "can override the default type name" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.type_name "Thingie"
      end
    end
    i = @model_class.new
    assert_equal "Thingie", i.mochigome_focus.type_name
  end

  it "cannot specify a nonsense type name" do
    assert_raises Mochigome::ModelSetupError do
      @model_class.class_eval do
        acts_as_mochigome_focus do |f|
          f.type_name 12345
        end
      end
    end
  end

  it "uses the attribute 'name' as the default focus name" do
    @model_class.class_eval do
      acts_as_mochigome_focus
    end
    i = @model_class.new
    assert_equal "Moby", i.mochigome_focus.name
  end

  it "can override the focus name with another method_name" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.name :last_name
      end
    end
    i = @model_class.new
    assert_equal "Dick", i.mochigome_focus.name
  end

  it "can override the focus name with a custom implementation" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.name lambda {|obj| "#{obj.name} #{obj.last_name}"}
      end
    end
    i = @model_class.new
    assert_equal "Moby Dick", i.mochigome_focus.name
  end

  it "uses the primary key as the default ordering" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.name :last_name
      end
    end
    assert_equal "id",
      @model_class.mochigome_focus_settings.get_ordering
  end

  it "can specify a custom ordering" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.name :last_name
        f.ordering :first_name
      end
    end
    assert_equal "first_name",
      @model_class.mochigome_focus_settings.get_ordering
  end

  it "can specify fields without name that act as fieldset named 'default'" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.fields ["a", "b"]
      end
    end
    i = @model_class.new(:a => "abc", :b => "xyz", :c => "123")
    expected = ActiveSupport::OrderedHash.new
    expected["a"] = "abc"
    expected["b"] = "xyz"
    assert_equal expected, i.mochigome_focus.field_data
    assert_equal expected, i.mochigome_focus.field_data([:default])
  end

  it "can specify and request fieldsets with custom names" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.fieldset :foo, ["c", "d"]
        f.fieldset :bar, ["e"]
        f.fieldset :zap, ["f"]
      end
    end
    i = @model_class.new(:c => "cat", :d => "dog", :e => "elephant", :f => "ferret")
    expected = ActiveSupport::OrderedHash.new
    expected["f"] = "ferret"
    expected["c"] = "cat"
    expected["d"] = "dog"
    assert_equal expected, i.mochigome_focus.field_data([:zap, :foo])
  end

  it "has no report focus data if no fields are specified" do
    @model_class.class_eval do
      acts_as_mochigome_focus
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    assert_empty i.mochigome_focus.field_data
  end

  it "can specify only some of its fields" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.fields ["b"]
      end
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    expected = ActiveSupport::OrderedHash.new
    expected["b"] = "xyz"
    assert_equal expected, i.mochigome_focus.field_data
  end

  it "can specify fields in a custom order" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.fields ["b", "a"]
      end
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    expected = ActiveSupport::OrderedHash.new
    expected["b"] = "xyz"
    expected["a"] = "abc"
    assert_equal expected, i.mochigome_focus.field_data
  end

  it "can specify fields with multiple calls" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.fields ["a"]
        f.fields ["b"]
      end
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    expected = ActiveSupport::OrderedHash.new
    expected["a"] = "abc"
    expected["b"] = "xyz"
    assert_equal expected, i.mochigome_focus.field_data
  end

  it "can specify fields with custom names" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.fields [{:Abraham => :a}, {:Barcelona => :b}]
      end
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    expected = ActiveSupport::OrderedHash.new
    expected["Abraham"] = "abc"
    expected["Barcelona"] = "xyz"
    assert_equal expected, i.mochigome_focus.field_data
  end

  it "can specify fields with custom implementations" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.fields [{:concat => lambda {|obj| obj.a + obj.b}}]
      end
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    expected = ActiveSupport::OrderedHash.new
    expected["concat"] = "abcxyz"
    assert_equal expected, i.mochigome_focus.field_data
  end

  it "cannot call f.fields with nonsense" do
    assert_raises Mochigome::ModelSetupError do
      @model_class.class_eval do
        acts_as_mochigome_focus do |f|
          f.fields 123
        end
      end
    end
    assert_raises Mochigome::ModelSetupError do
      @model_class.class_eval do
        acts_as_mochigome_focus do |f|
          f.fields [789]
        end
      end
    end
  end

  [:name, :id, :type, :internal_type].each do |n|
    it "cannot specify fields named the same as reserved term '#{n}'" do
      assert_raises Mochigome::ModelSetupError do
        @model_class.class_eval do
          acts_as_mochigome_focus do |f|
            f.fields [n]
          end
        end
      end
      assert_raises Mochigome::ModelSetupError do
        @model_class.class_eval do
          acts_as_mochigome_focus do |f|
            f.fields [n.to_s.titleize]
          end
        end
      end
      assert_raises Mochigome::ModelSetupError do
        @model_class.class_eval do
          acts_as_mochigome_focus do |f|
            f.fields [{n => :foo}]
          end
        end
      end
    end
  end

  # Actual use of aggregations is tested in query_test.

  it "can specify aggregated data to be collected" do
    @model_class.class_eval do
      has_mochigome_aggregations do |a|
        a.fields [
          :average_x,
          :Count,
          {"bloo" => :sum_x}
        ]
      end
    end
    assert_equal [
      "Whales average x",
      "Whales Count",
      "bloo"
    ], @model_class.mochigome_aggregation_settings.options[:fields].map{|a| a[:name]}
  end

  it "can specify aggregations with custom names" do
    @model_class.class_eval do
      has_mochigome_aggregations do |a|
        a.fields [{"Mean X" => "avg x"}]
      end
    end
    assert_equal [
      "Mean X"
    ], @model_class.mochigome_aggregation_settings.options[:fields].map{|a| a[:name]}
  end

  it "can specify aggregations with custom arel expressions for value" do
    @model_class.class_eval do
      has_mochigome_aggregations do |a|
        a.fields [{"The Answer" => [:sum, lambda{|t| t[:some_number_column]*2}]}]
      end
    end
    assert_equal [
      "The Answer"
    ], @model_class.mochigome_aggregation_settings.options[:fields].map{|a| a[:name]}
  end

  it "can specify aggregations with custom arel expressions for aggregation" do
    @model_class.class_eval do
      has_mochigome_aggregations do |a|
        a.fields [{"The Answer" => [lambda{|a| a.sum}, :some_col]}]
      end
    end
    assert_equal [
      "The Answer"
    ], @model_class.mochigome_aggregation_settings.options[:fields].map{|a| a[:name]}
  end

  it "cannot call aggregation fields method with nonsense" do
    assert_raises Mochigome::ModelSetupError do
      @model_class.class_eval do
        has_mochigome_aggregations do |a|
          a.fields 3
        end
      end
    end
    assert_raises Mochigome::ModelSetupError do
      @model_class.class_eval do
        has_mochigome_aggregations do |a|
          a.fields [42]
        end
      end
    end
  end

  it "can specify hidden aggregation fields" do
    @model_class.class_eval do
      has_mochigome_aggregations do |a|
        a.hidden_fields [:count]
      end
    end
    agg = @model_class.mochigome_aggregation_settings.options[:fields].first
    assert_equal "Whales count", agg[:name]
    assert agg[:hidden]
  end

  it "can specify aggregation fields in ruby which post-process regular fields" do
    @model_class.class_eval do
      has_mochigome_aggregations do |a|
        a.hidden_fields [:count]
        a.fields_in_ruby [
          {"Double count" => lambda{|row| row["Whales count"]*2}}
        ]
      end
    end
    agg = @model_class.mochigome_aggregation_settings.options[:fields].last
    assert_equal "Double count", agg[:name]
    assert agg[:in_ruby]
  end

  def assoc_query_words_match(tbl, cond, words)
    q = Arel::Table.new(:foo).project(Arel.star).join(Arel::Table.new(tbl)).on(cond).to_sql
    cur_word = words.shift
    q.split(/[ .]/).each do |s_word|
      if s_word.gsub(/["'`]+/, '').downcase == cur_word.downcase
        cur_word = words.shift
      end
    end
    return true if cur_word.nil?
    raise "AQWM '#{q}': NO WORD MATCH ON '#{cur_word}'"
  end

  it "can convert a belongs_to association into a lambda that processes an arel relation" do
    @model_class.class_eval do
      belongs_to :store
    end
    assert assoc_query_words_match "stores", @model_class.assoc_condition(:store),
      %w{select * from foo join stores on fake store_id = stores id}
  end

  it "can convert a has_many association into an arel relation lambda" do
    @model_class.class_eval do
      has_many :stores
    end
    assert assoc_query_words_match "stores", @model_class.assoc_condition(:stores),
      %w{select * from foo join stores on fake id = stores whale_id}
  end

  it "can convert a has_one association into an arel relation lambda" do
    @model_class.class_eval do
      has_one :store
    end
    assert assoc_query_words_match "stores", @model_class.assoc_condition(:store),
      %w{select * from foo join stores on fake id = stores whale_id}
  end

  it "raises AssociationError on attempting to arelify a non-extant assoc" do
    assert_raises Mochigome::AssociationError do
      Store.assoc_condition(:dinosaurs)
    end
  end

  # TODO: Test proper conditions used on polymorphic assocs
end
