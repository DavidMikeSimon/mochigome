unless ActiveRecord::ConnectionAdapters::ConnectionPool.methods.include?("table_exists?")
  module Mochigome
    class ColumnsHashProxy
      def initialize(pool)
        @pool = pool
        @cache = HashWithIndifferentAccess.new
      end

      def [](table_name)
        cached(table_name)
      end

      private

      def cached(table_name)
        return @cache[table_name] if @cache.has_key?(:table_name)

        @cache[table_name] = h = HashWithIndifferentAccess.new
        @pool.with_connection do |c|
          c.columns(table_name).each do |col|
            h[col.name] = col
          end
        end
        return h
      end
    end
  end

  class ActiveRecord::ConnectionAdapters::ConnectionPool
    def table_exists?(name)
      ActiveRecord::Base.connection_pool.with_connection do |c|
        c.table_exists?(name)
      end
    end

    @@columns_hash_proxy = nil
    def columns_hash
      @@columns_hash_proxy ||= Mochigome::ColumnsHashProxy.new(self)
    end
  end

  # FIXME: Shouldn't use select_rows anymore
  class ActiveRecord::ConnectionAdapters::SQLiteAdapter
    def select_rows(sql, name = nil)
      execute(sql, name).map do |row|
        row.keys.select{|key| key.is_a? Integer}.sort.map{|key| row[key]}
      end
    end
  end
end
