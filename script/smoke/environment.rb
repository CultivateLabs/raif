# frozen_string_literal: true

# Local setup checks the smoke runner makes before it calls any provider. Without them, a stale
# database fails every check with an error such as ActiveModel::UnknownAttributeError, which
# reads like a model failure.
#
# The dummy app's own migration context covers only spec/dummy/db/migrate. Engine migrations run
# from db/migrate through `bin/rails app:db:migrate`, so the check reads both directories.
module Smoke
  module Environment
    def self.migration_context
      paths = Raif::Engine.paths["db/migrate"].existent + Rails.application.paths["db/migrate"].existent
      ActiveRecord::MigrationContext.new(paths.uniq)
    end

    # Returns a message describing what is wrong with the local database, or nil when it is ready.
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
