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
require 'minitest/autorun'

module MiniTest
  def self.filter_backtrace(backtrace)
    backtrace = backtrace.select do |e|
      if ENV['FULL_BACKTRACE']
        true
      else
        !(e.include?("/ruby/") || e.include?("/gems/"))
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


require 'factories'
MiniTest::Unit::TestCase.send(:include, Factory::Syntax::Methods)

MiniTest::Unit::TestCase.add_setup_hook do
  ActiveRecord::Migration.verbose = false
  ActiveRecord::Migrator.migrate("#{Rails.root}/db/migrate") # Migrations in the test app
end
