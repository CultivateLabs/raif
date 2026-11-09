# frozen_string_literal: true

# Checked before any provider call: a stale database otherwise fails every smoke check with
# errors that look like model failures.
#
# The dummy app's migration context covers only spec/dummy/db/migrate. Engine migrations run
# from db/migrate through `bin/rails app:db:migrate`, so both directories are read.
module Smoke
  module Environment
    def self.migration_context
      paths = Raif::Engine.paths["db/migrate"].existent + Rails.application.paths["db/migrate"].existent
      ActiveRecord::MigrationContext.new(paths.uniq)
    end

    def self.database_problem(context = migration_context)
      ran_versions = context.get_all_versions
      pending = context.migrations.reject { |migration| ran_versions.include?(migration.version) }
      return if pending.empty?

      <<~MESSAGE
        The #{database_name} database has #{pending.size} pending #{"migration".pluralize(pending.size)}:

        #{pending.map { |migration| "  #{migration.version} #{migration.name}" }.join("\n")}

        Run `bin/rails app:db:migrate` from the repository root, then run bin/smoke again.
      MESSAGE
    rescue ActiveRecord::NoDatabaseError
      <<~MESSAGE
        The #{database_name} database does not exist.

        Run `bin/rails app:db:create app:db:migrate` from the repository root, then run bin/smoke again.
      MESSAGE
    end

    def self.database_name
      ActiveRecord::Base.connection_db_config.database
    end
  end
end
