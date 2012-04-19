# Pretend the mochigome gem is a plugin for the test environment
mochi_path = File.expand_path "#{File.dirname(__FILE__)}/../../../../../lib/"
$LOAD_PATH.unshift mochi_path
require "mochigome.rb"
