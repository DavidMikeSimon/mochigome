require 'aggregator'
require 'exceptions'
require 'data_set'
require 'model_extensions'
require 'version'

ActiveRecord::Base.send(:include, Ernie::ModelExtensions)
