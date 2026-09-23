# frozen_string_literal: true

module Raif
  # Points `raif evals` at its own database, so a run neither collides with the host's test suite on
  # the test database nor leaves a spec waiting on an eval's uncommitted rows. Evals still boot in
  # the test environment, because that is where host apps load FactoryBot, WebMock and friends; only
  # the database name changes, and only when Raif.config.evals_database_suffix is set.
  module EvalsDatabase
    # Nothing to name: an in-memory SQLite database is already private to the process.
    IN_MEMORY_DATABASES = [":memory:"].freeze

    class << self
      def enabled?
        Raif.running_evals? && Rails.env.test? && Raif.config.evals_database_suffix.present?
      end

      # Renames every database the test environment connects to, replicas included, so a host with
      # more than one database cannot leave some of its models writing to the test database. Runs
      # in after_initialize, once the host's Raif initializer has set the suffix. Pools established
      # before then - eager loading runs connects_to during boot - share these config objects, so
      # renaming in place and dropping any open connections moves them too.
      #
      # Prepared in the same hook as the rename, not later: the rest of boot can already query the
      # renamed database - routes load after after_initialize and can load models whose class
      # bodies read the schema - and a missing or empty database fails the boot there.
      def configure!
        return unless enabled?

        ActiveSupport.on_load(:active_record) do
          Raif::EvalsDatabase.switch_to(Raif.config.evals_database_suffix)
        end
      end

      def switch_to(suffix)
        rename(ActiveRecord::Base.configurations, env_name: Rails.env, suffix: suffix)
        ActiveRecord::Base.connection_handler.clear_all_connections!(:all)
        prepare!
      end

      def rename(configurations, env_name:, suffix:)
        configurations.configs_for(env_name: env_name, include_hidden: true).each do |db_config|
          # A non-replica that opts out of database tasks is a database the host does not manage,
          # such as a shared read-only warehouse, so there is no evals copy of it to point at.
          next if db_config.database.blank? || (!db_config.replica? && !db_config.database_tasks?)

          db_config._database = name_for(db_config.database, suffix: suffix)
        end
      end

      # app_test becomes app_raif_evals. A name without a _test suffix keeps its name and gains the
      # suffix, and a SQLite file keeps its extension: db/test.sqlite3 becomes db/test_raif_evals.sqlite3.
      def name_for(database, suffix:)
        return database if IN_MEMORY_DATABASES.include?(database) || database.include?("mode=memory")

        extension = File.extname(database)
        extension = "" unless extension.match?(/\A\.sqlite3?\z/)
        base = database.delete_suffix(extension)

        "#{base.delete_suffix("_test")}#{suffix}#{extension}"
      end

      # Creates each evals database that does not exist and loads the schema into any whose schema
      # is out of date, the same way Rails prepares its parallel test databases. An up-to-date
      # database is truncated instead, so every run starts from empty tables.
      def prepare!
        verbose_was, ENV["VERBOSE"] = ENV["VERBOSE"], "false"

        ActiveRecord::Base.configurations.configs_for(env_name: Rails.env).each do |db_config|
          reconstruct_from_schema(db_config)
        end
      ensure
        ActiveRecord::Base.establish_connection
        ENV["VERBOSE"] = verbose_was
      end

      def database_names
        ActiveRecord::Base.configurations.configs_for(env_name: Rails.env).map(&:database)
      end

    private

      # Rails 8.0 dropped the format argument: the format comes from the db config instead.
      def reconstruct_from_schema(db_config)
        if ActiveRecord.version >= Gem::Version.new("8.0")
          ActiveRecord::Tasks::DatabaseTasks.reconstruct_from_schema(db_config)
        else
          ActiveRecord::Tasks::DatabaseTasks.reconstruct_from_schema(db_config, ActiveRecord.schema_format)
        end
      end
    end
  end
end
