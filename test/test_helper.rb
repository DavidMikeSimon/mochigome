ENV['RAILS_ENV'] = ENV['NO_MINITEST'] ? "development" : "test"

begin
  # Used when running test files directly
  d = File.expand_path File.dirname(__FILE__)
  $LOAD_PATH << d
  $LOAD_PATH << "#{d}/../lib"
  $LOAD_PATH << "#{d}/app_root/config"
  require "environment"
rescue LoadError
  # This is needed for root-level rake task 'test'
  require "app_root/config/environment"
end

require 'rubygems'

if ENV['NO_MINITEST']
  ActiveRecord::Migration.verbose = false
  ActiveRecord::Migrator.migrate("#{Rails.root}/db/migrate") # Migrations in the test app
else
  require 'minitest/autorun'
  require 'redgreen'

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
end
