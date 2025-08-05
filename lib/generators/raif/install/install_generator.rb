# frozen_string_literal: true

require "rails/generators"
require "rails/generators/migration"

module Raif
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      def self.next_migration_number(path)
        next_migration_number = current_migration_number(path) + 1
        ActiveRecord::Migration.next_migration_number(next_migration_number)
      end

      def copy_initializer
        template "initializer.rb", "config/initializers/raif.rb"
      end

      def install_migrations
        rake "raif:install:migrations"
      end

      def add_engine_route
        routes_file = "config/routes.rb"

        if File.exist?(routes_file)
          routes_content = File.read(routes_file)
          if routes_content.include?("mount Raif::Engine")
            say "Raif is already mounted in #{routes_file}, skipping route", :yellow
            return
          end
        end

        route 'mount Raif::Engine => "/raif"'
      end

      def setup_evals
        say "\nSetting up Raif evals...", :green
        generate "raif:evals:setup"
      end
    end
  end
end
