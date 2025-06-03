# frozen_string_literal: true

module Raif
  module MigrationChecker
    class << self
      def uninstalled_migrations
        engine_migration_names = engine_migration_names_from_context
        ran_migration_names = ran_migration_names_from_host

        engine_migration_names - ran_migration_names
      end

      def check_and_warn!
        return unless defined?(Rails) && Rails.application

        uninstalled = uninstalled_migrations
        return if uninstalled.empty?

        warning_message = build_warning_message(uninstalled)

        # Output to both logger and STDOUT to ensure visibility
        Rails.logger&.warn(warning_message)
        warn warning_message
      end

    private

      def engine_migration_names_from_context
        engine_paths = Raif::Engine.paths["db/migrate"].existent
        return [] if engine_paths.empty?

        ActiveRecord::MigrationContext.new(engine_paths).migrations.map(&:name)
      rescue => e
        Rails.logger&.debug("Raif: Could not load engine migrations: #{e.message}")
        []
      end

      def ran_migration_names_from_host
        return [] unless defined?(Rails) && Rails.application

        app_paths = Rails.application.paths["db/migrate"].expanded
        return [] if app_paths.empty?

        ctx = ActiveRecord::MigrationContext.new(app_paths)
        ran_versions = ctx.get_all_versions
        ctx.migrations.select{|m| ran_versions.include?(m.version) }.map(&:name)
      rescue ActiveRecord::NoDatabaseError
        # Database doesn't exist yet, so no migrations have been run
        []
      rescue => e
        Rails.logger&.debug("Raif: Could not load migration status: #{e.message}")
        []
      end

      def build_warning_message(uninstalled_migration_names)
        <<~WARNING
          \e[33m
          ⚠️  RAIF MIGRATION WARNING ⚠️

          The following Raif migrations have not been run in your application:

          #{uninstalled_migration_names.map { |name| "  • #{name}" }.join("\n")}

          To install and run these migrations:

            rails raif:install:migrations
            rails db:migrate

          \e[0m
        WARNING
      end
    end
  end
end
