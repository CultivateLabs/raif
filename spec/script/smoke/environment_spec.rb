# frozen_string_literal: true

require "rails_helper"
require Raif::Engine.root.join("script/smoke/environment")

RSpec.describe Smoke::Environment do
  describe ".database_problem" do
    let(:migrations) do
      [
        ActiveRecord::MigrationProxy.new("CreateWidgets", 20260101000000, "x/20260101000000_create_widgets.rb", nil),
        ActiveRecord::MigrationProxy.new("AddSizeToWidgets", 20260202000000, "x/20260202000000_add_size_to_widgets.rb", nil)
      ]
    end
    let(:context){ instance_double(ActiveRecord::MigrationContext, migrations: migrations) }

    it "returns nil when every migration has run" do
      allow(context).to receive(:get_all_versions).and_return([20260101000000, 20260202000000])

      expect(described_class.database_problem(context)).to be_nil
    end

    it "names each pending migration and the command that runs them" do
      allow(context).to receive(:get_all_versions).and_return([20260101000000])

      message = described_class.database_problem(context)

      expect(message).to include("1 pending migration", "20260202000000 AddSizeToWidgets", "bin/rails app:db:migrate")
      expect(message).not_to include("CreateWidgets")
    end

    it "explains how to create the database when it does not exist" do
      allow(context).to receive(:get_all_versions).and_raise(ActiveRecord::NoDatabaseError)

      expect(described_class.database_problem(context)).to include("bin/rails app:db:create app:db:migrate")
    end
  end

  describe ".migration_context" do
    it "covers the engine migrations as well as the app's own" do
      paths = described_class.migration_context.migrations_paths.map { |path| File.expand_path(path) }

      expect(paths).to include(Raif::Engine.root.join("db/migrate").to_s, Rails.root.join("db/migrate").to_s)
    end
  end
end
