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

desc 'Test Ernie'
Rake::TestTask.new(:test) do |t|
  common_test_settings(t)
end

desc 'Generate documentation for Ernie.'
RDoc::Task.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
  rdoc.title    = 'Ernie'
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
  s.name         = "ernie"
  s.version      = Ernie::VERSION
  s.authors      = ["David Mike Simon"]
  s.email        = "david.mike.simon@gmail.com"
  s.homepage     = "http://github.com/DavidMikeSimon/ernie"
  s.summary      = "User-customizable report generator"
  s.description  = "Ernie lets your users customize their own Ruport report designs by combining developer-provided pieces"

  s.files        = `git ls-files .`.split("\n") - [".gitignore"]
  s.platform     = Gem::Platform::RUBY
  s.require_path = 'lib'
  s.rubyforge_project = '[none]'

  s.add_dependency('ruport', '1.6.3')
  s.add_dependency('ruport-util', '0.14.0')
end

Gem::PackageTask.new(gemspec) do |pkg|
end
