require 'version'
require 'exceptions'
require 'data_node'
require 'query'
require 'model_extensions'

ActiveRecord::Base.send(:include, Ernie::ModelExtensions)
