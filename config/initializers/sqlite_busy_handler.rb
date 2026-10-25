# SQLite allows one writer at a time. Rails 7.1 waits for the write lock with
# sqlite3's busy_timeout, which sleeps in C *while holding Ruby's GVL*, so the
# thread that owns the lock cannot run to COMMIT and concurrent writers in the
# same process (Puma threads) fail with "database is locked".
#
# This installs a Ruby-level busy handler that sleeps without the GVL and
# retries until the configured `timeout` (database.yml) elapses — the approach
# Rails 8 adopted. Not needed with PostgreSQL/MySQL.
module SqliteBusyHandler
  RETRY_INTERVAL = 0.002 # seconds

  private

  def configure_connection
    super

    timeout = self.class.type_cast_config_to_integer(@config[:timeout]).to_i / 1000.0
    max_retries = (timeout / RETRY_INTERVAL).ceil
    @raw_connection.busy_handler do |count|
      next false if count >= max_retries

      sleep RETRY_INTERVAL
      true
    end
  end
end

ActiveSupport.on_load(:active_record_sqlite3adapter) { prepend SqliteBusyHandler }
