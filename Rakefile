require 'rubygems'
require 'rake'
require 'rake/testtask'
require 'rdoc/task'
require 'rubygems/package_task'
require 'rcov/rcovtask'
require 'ruby-prof/task'

require 'bundler/setup'
Bundler.require(:default)

def common_test_settings(t)
  t.libs << 'lib'
  t.libs << 'test'
  t.pattern = 'test/**/*_test.rb'
  t.verbose = true
end

desc 'Default: run unit and functional tests.'
task :default => :test

desc 'Test Mochigome'
Rake::TestTask.new(:test) do |t|
  common_test_settings(t)
end

desc 'Run tests automatically as files change'
task :watchr do |t|
  exec 'watchr test/test.watchr'
end

desc 'Generate documentation for Mochigome.'
RDoc::Task.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
  rdoc.title    = 'Mochigome'
  rdoc.options << '--line-numbers' << '--inline-source'
  rdoc.rdoc_files.include('README')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

Rcov::RcovTask.new(:rcov) do |t|
  common_test_settings(t)
  t.pattern = 'test/unit/*_test.rb' # Don't care about coverage added by functional tests
  t.rcov_opts << '-o coverage -x "/ruby/,/gems/,/test/,/migrate/"'
end
  
RubyProf::ProfileTask.new(:profile) do |t|
  common_test_settings(t)
  t.output_dir = "#{File.dirname(__FILE__)}/profile"
  t.printer = :call_tree
  t.min_percent = 10
end

require 'lib/version'
gemspec = Gem::Specification.new do |s|
  s.name         = "mochigome"
  s.version      = Mochigome::VERSION
  s.authors      = ["David Mike Simon"]
  s.email        = "david.mike.simon@gmail.com"
  s.homepage     = "http://github.com/DavidMikeSimon/mochigome"
  s.summary      = "User-customizable report generator"
  s.description  = "Mochigome builds sophisticated report datasets from your ActiveRecord models"
  s.files        = `git ls-files .`.split("\n") - [".gitignore"]
  s.platform     = Gem::Platform::RUBY
  s.require_path = 'lib'
  s.rubyforge_project = '[none]'

  s.add_dependency('ruport')
  s.add_dependency('ruport-util')
  s.add_dependency('rgl')
end

Gem::PackageTask.new(gemspec) do |pkg|
end
