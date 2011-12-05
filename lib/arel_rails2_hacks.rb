unless ActiveRecord::ConnectionAdapters::ConnectionPool.methods.include?("table_exists?")
  class ActiveRecord::ConnectionAdapters::ConnectionPool
    def table_exists?(name)
      ActiveRecord::Base.connection_pool.with_connection do |c|
        c.table_exists?(name)
      end
    end
  end
end
