# frozen_string_literal: true

module Raif
  # Points `raif evals` at its own database, so a run neither collides with the host's test suite on
  # the test database nor leaves a spec waiting on an eval's uncommitted rows. Evals still boot in
  # the test environment, because that is where host apps load FactoryBot, WebMock and friends; only
  # the database name changes, and only when Raif.config.evals_database_suffix is set.
  module EvalsDatabase
    # Nothing to name: an in-memory SQLite database is already private to the process.
    IN_MEMORY_DATABASES = [":memory:"].freeze

    # Another `raif evals` run is using the same evals database.
    class InUseError < StandardError; end

    class << self
      def enabled?
        Raif.running_evals? && Rails.env.test? && Raif.config.evals_database_suffix.present?
      end

      def in_memory?(database)
        IN_MEMORY_DATABASES.include?(database) || database.include?("mode=memory")
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
          Raif::EvalsDatabase.switch_to(Raif.config.evals_database_suffix, replacing: "_test", lock: true)
        end
      end

      # Moves a forked eval worker onto a database of its own - app_raif_evals becomes
      # app_raif_evals_2 - so its uncommitted rows cannot hold up the other workers. Two workers
      # sharing one database block on any unique index both write the same key to, which a shared
      # fixture or a repeated case does on every execution.
      def use_worker_database!(worker_number)
        switch_to("_#{worker_number}", replacing: nil)
      end

      def switch_to(suffix, replacing:, lock: false)
        rename(ActiveRecord::Base.configurations, env_name: Rails.env, suffix: suffix, replacing: replacing)
        lock! if lock
        ActiveRecord::Base.connection_handler.clear_all_connections!(:all)
        prepare!
      end

      def rename(configurations, env_name:, suffix:, replacing: "_test")
        managed_configs(configurations, env_name: env_name).each do |db_config|
          db_config._database = name_for(db_config.database, suffix: suffix, replacing: replacing)
        end
      end

      # app_test becomes app_raif_evals. A name without a _test suffix keeps its name and gains the
      # suffix, and a SQLite file keeps its extension: db/test.sqlite3 becomes db/test_raif_evals.sqlite3.
      # A worker database passes replacing: nil, since its name only gains the worker number. A
      # SQLite URI keeps its query: file:db/test.sqlite3?mode=rwc becomes file:db/test_raif_evals.sqlite3?mode=rwc.
      def name_for(database, suffix:, replacing: "_test")
        return database if in_memory?(database)

        path, separator, query = database.start_with?("file:") ? database.partition("?") : [database, "", ""]
        extension = File.extname(path)
        extension = "" unless extension.match?(/\A\.sqlite3?\z/)
        base = path.delete_suffix(extension)
        base = base.delete_suffix(replacing) if replacing

        "#{base}#{suffix}#{extension}#{separator}#{query}"
      end

      # Creates each evals database that does not exist and loads the schema into any whose schema
      # is out of date, the same way Rails prepares its parallel test databases. An up-to-date
      # database is truncated instead, so every run starts from empty tables.
      def prepare!
        verbose_was, ENV["VERBOSE"] = ENV["VERBOSE"], "false"

        managed_configs(ActiveRecord::Base.configurations, env_name: Rails.env).uniq(&:database).each do |db_config|
          reconstruct_from_schema(db_config)
        end
      ensure
        ActiveRecord::Base.establish_connection
        ENV["VERBOSE"] = verbose_was
      end

      # Held for the life of the run, so a second run cannot truncate this one's databases under it.
      # Preparing a database truncates it, and so does each worker preparing its own. The workers
      # inherit the lock when they fork, and the worker databases are named after the locked one,
      # so this one lock covers them too.
      def lock!
        database = database_names.first
        return if database.blank? || in_memory?(database)

        path = Rails.root.join("tmp", "raif_evals-#{database.gsub(/[^\w.-]+/, "_")}.lock")
        FileUtils.mkdir_p(path.dirname)
        file = File.open(path, File::RDWR | File::CREAT)

        unless file.flock(File::LOCK_EX | File::LOCK_NB)
          file.close
          raise InUseError, "Another raif evals run is using the #{database} database. Starting this run would " \
            "truncate its tables under it. Wait for that run to finish, or give this run a database of its own " \
            "with a different Raif.config.evals_database_suffix."
        end

        # Kept open: closing the file, or letting it be garbage collected, releases the lock.
        @lock_file = file
      end

      def database_names
        managed_configs(ActiveRecord::Base.configurations, env_name: Rails.env).map(&:database).uniq
      end

    private

      # Every database the evals copy of an environment is made of, writers first. A non-replica
      # that opts out of database tasks is a database the host does not manage, such as a shared
      # read-only warehouse, so there is no evals copy of it. Replicas are hidden from configs_for
      # by default but are included here: one that shares its writer's database is prepared with
      # the writer, and one with a database of its own has to be prepared too.
      def managed_configs(configurations, env_name:)
        writers, replicas = configurations.configs_for(env_name: env_name, include_hidden: true)
          .reject { |db_config| db_config.database.blank? || (!db_config.replica? && !db_config.database_tasks?) }
          .partition { |db_config| !db_config.replica? }

        writers + replicas
      end

      # Rails 8.0 dropped the format argument: the format comes from the db config instead.
      def reconstruct_from_schema(db_config)
        check_replica_schema(db_config)

        if ActiveRecord.version >= Gem::Version.new("8.0")
          ActiveRecord::Tasks::DatabaseTasks.reconstruct_from_schema(db_config)
        else
          ActiveRecord::Tasks::DatabaseTasks.reconstruct_from_schema(db_config, ActiveRecord.schema_format)
        end
      end

      # Rails loads a replica from <name>_schema.rb, which db:schema:dump never writes, so a replica
      # with a database of its own needs its writer's schema named with schema_dump. Without it,
      # Rails fails with advice to run db:migrate, which cannot help.
      def check_replica_schema(db_config)
        return unless db_config.replica?

        path = ActiveRecord::Tasks::DatabaseTasks.schema_dump_path(db_config)
        return if path && File.exist?(path)

        raise Raif::Errors::InvalidConfigError,
          "The #{db_config.name} replica has a database of its own (#{db_config.database}), so raif evals has to " \
            "load a schema into it, but it has no schema file#{" at #{path}" if path}. Point it at its writer's " \
            "database in the test environment, or set schema_dump in its config to its writer's schema file."
      end
    end
  end
end
