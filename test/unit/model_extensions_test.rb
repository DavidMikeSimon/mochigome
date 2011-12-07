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

  it "can specify fields" do
    @model_class.class_eval do
      acts_as_mochigome_focus do |f|
        f.fields ["a", "b"]
      end
    end
    i = @model_class.new(:a => "abc", :b => "xyz")
    expected = ActiveSupport::OrderedHash.new
    expected["a"] = "abc"
    expected["b"] = "xyz"
    assert_equal expected, i.mochigome_focus.field_data
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

  it "appears in Mochigome's global model list if it acts_as_mochigome_focus" do
    assert !Mochigome.reportFocusModels.include?(@model_class)
    @model_class.class_eval do
      acts_as_mochigome_focus
    end
    assert Mochigome.reportFocusModels.include?(@model_class)
  end

  it "can specify aggregated data to be collected" do
    @model_class.class_eval do
      has_mochigome_aggregations [
        :average_x,
        :Count,
        {"bloo" => :sum_x}
      ]
    end
    # The actual effectiveness of these lambdas will be tested in query_test.
    assert_equal [
      "Whales average x",
      "Whales Count",
      "bloo"
    ], @model_class.mochigome_aggregations.map{|a| a[:name]}
  end

  it "can specify aggregations with custom names" do
    @model_class.class_eval do
      has_mochigome_aggregations [{"Mean X" => "avg x"}]
    end
    assert_equal [
      "Mean X"
    ], @model_class.mochigome_aggregations.map{|a| a[:name]}
  end

  it "can specify aggregations with custom arel expressions" do
    @model_class.class_eval do
      has_mochigome_aggregations [{"The Answer" => lambda{|r| }}]
    end
    assert_equal [
      "The Answer"
    ], @model_class.mochigome_aggregations.map{|a| a[:name]}
  end

  it "cannot call has_mochigome_aggregations with nonsense" do
    assert_raises Mochigome::ModelSetupError do
      @model_class.class_eval do
        has_mochigome_aggregations 3
      end
    end
    assert_raises Mochigome::ModelSetupError do
      @model_class.class_eval do
        has_mochigome_aggregations [42]
      end
    end
  end

  def assoc_query_words_match(assoc, words)
    q = assoc.call(Arel::Table.new(:foo).project(Arel.sql('*'))).to_sql
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
    assert assoc_query_words_match @model_class.arelified_assoc(:store),
      %w{select * from foo join stores on fake store_id = stores id}
  end

  it "can convert a has_many association into an arel relation lambda" do
    @model_class.class_eval do
      has_many :stores
    end
    assert assoc_query_words_match @model_class.arelified_assoc(:stores),
      %w{select * from foo join stores on fake id = stores whale_id}
  end

  it "can convert a has_one association into an arel relation lambda" do
    @model_class.class_eval do
      has_one :store
    end
    assert assoc_query_words_match @model_class.arelified_assoc(:store),
      %w{select * from foo join stores on fake id = stores whale_id}
  end

  it "raises AssociationError on attempting to arelify a non-extant assoc" do
    assert_raises Mochigome::AssociationError do
      Store.arelified_assoc(:dinosaurs)
    end
  end
end
