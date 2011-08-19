ENV['RAILS_ENV'] = 'test'

prev_dir = Dir.getwd
begin
  Dir.chdir("#{File.dirname(__FILE__)}/..")
  
  begin
    # Used when running test files directly
    $LOAD_PATH << "#{File.dirname(__FILE__)}/../lib"
    require "#{File.dirname(__FILE__)}/app_root/config/environment"
  rescue LoadError
    # This is needed for root-level rake task 'test'
    require "app_root/config/environment"
  end
ensure
  Dir.chdir(prev_dir)
end

require 'rubygems'
require 'test/unit/util/backtracefilter'
require 'test_help'

# Try to load the redgreen test console outputter, if it's available
begin
  require 'redgreen'
rescue LoadError
end

# Monkey patch the backtrace filter to include project source files 
module Test::Unit::Util::BacktraceFilter
  def filter_backtrace(backtrace, prefix = nil)
    backtrace = backtrace.select do |e|
      if ENV['FULL_BACKTRACE']
        true
      else
        e.include?("ernie") || !(e.include?("/ruby/") || e.include?("/gems/"))
      end
    end
    
    common_prefix = nil
    backtrace.each do |elem|
      next if elem.start_with? "./"
      if common_prefix
        until elem.start_with? common_prefix
          common_prefix.chop!
        end
      else
        common_prefix = String.new(elem)
      end
    end
    
    return backtrace.map do |element|
      if element.start_with? common_prefix && common_prefix.size < element.size
        element[common_prefix.size, element.size]
      elsif element.start_with? "./"
        element[2, element.size]
      elsif element.start_with?(Dir.getwd)
        element[Dir.getwd.size+1, element.size]
      else
        element
      end
    end
  end
end

class Test::Unit::TestCase
  include Test::Unit::Util::BacktraceFilter

  def setup
    ActiveRecord::Migration.verbose = false
    ActiveRecord::Migrator.migrate("#{Rails.root}/db/migrate") # Migrations for the testing pseudo-app
  end

  # Alias for should, scans better sometimes
  def self.could(verb, &block)
    context_could :should, verb, &block
  end
  def self.could_eventually(verb, &block)
    context_could :should_eventually, verb, &block
  end

  private

  def self.context_could(method, verb, &block)
    Shoulda::Context.current_context.send(method, "be able to #{verb}", &block)
  end
end
