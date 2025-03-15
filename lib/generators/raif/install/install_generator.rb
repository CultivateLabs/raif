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
        route 'mount Raif::Engine => "/raif"'
      end
    end
  end
end
