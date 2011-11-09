require 'arel'
Arel::Table.engine = Arel::Sql::Engine.new(ActiveRecord::Base)
