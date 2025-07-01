# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::MigrationChecker do
  describe ".uninstalled_migrations" do
    before do
      # Mock engine migration names
      allow(described_class).to receive(:engine_migration_names_from_context).and_return([
        "CreateRaifTables",
        "AddResponseFormatToRaifConversations",
        "AddCostColumnsToRaifModelCompletions"
      ])
    end

    context "when all migrations have been run" do
      before do
        allow(described_class).to receive(:ran_migration_names_from_host).and_return([
          "CreateRaifTables",
          "AddResponseFormatToRaifConversations",
          "AddCostColumnsToRaifModelCompletions"
        ])
      end

      it "returns an empty array" do
        expect(described_class.uninstalled_migrations).to be_empty
      end
    end

    context "when some migrations have not been run" do
      before do
        allow(described_class).to receive(:ran_migration_names_from_host).and_return([
          "CreateRaifTables"
        ])
      end

      it "returns the unrun migrations" do
        uninstalled = described_class.uninstalled_migrations
        expect(uninstalled).to include("AddResponseFormatToRaifConversations")
        expect(uninstalled).to include("AddCostColumnsToRaifModelCompletions")
        expect(uninstalled).not_to include("CreateRaifTables")
      end
    end

    context "when no migrations have been run" do
      before do
        allow(described_class).to receive(:ran_migration_names_from_host).and_return([])
      end

      it "returns all engine migrations" do
        uninstalled = described_class.uninstalled_migrations
        expect(uninstalled.size).to eq(3)
        expect(uninstalled).to include("CreateRaifTables")
        expect(uninstalled).to include("AddResponseFormatToRaifConversations")
        expect(uninstalled).to include("AddCostColumnsToRaifModelCompletions")
      end
    end
  end

  describe ".check_and_warn!" do
    context "when there are uninstalled migrations" do
      before do
        allow(described_class).to receive(:uninstalled_migrations).and_return([
          "CreateRaifTables"
        ])
        allow(Rails).to receive(:logger).and_return(double("logger", warn: nil))
      end

      it "outputs a warning" do
        expect { described_class.check_and_warn! }.to output(/RAIF MIGRATION WARNING/).to_stderr
      end

      it "logs a warning" do
        expect(Rails.logger).to receive(:warn).with(/RAIF MIGRATION WARNING/)
        described_class.check_and_warn!
      end
    end

    context "when all migrations have been run" do
      before do
        allow(described_class).to receive(:uninstalled_migrations).and_return([])
      end

      it "does not output a warning" do
        expect { described_class.check_and_warn! }.not_to output.to_stderr
      end
    end
  end

  describe ".engine_migration_names_from_context" do
    it "returns migration names from the engine paths" do
      # This is an integration test that uses the actual engine paths
      migration_names = described_class.send(:engine_migration_names_from_context)

      expect(migration_names).to be_an(Array)
      expect(migration_names).to include("CreateRaifTables")
    end
  end

  describe ".ran_migration_names_from_host" do
    context "when database exists and migrations have been run" do
      it "returns the names of run migrations" do
        # Mock the migration context and versions
        mock_ctx = double("migration_context")
        mock_migration = double("migration", name: "CreateUsers", version: 123)
        mock_paths = double("paths", expanded: ["/fake/path"])

        allow(Rails.application).to receive(:paths).and_return({ "db/migrate" => mock_paths })
        allow(ActiveRecord::MigrationContext).to receive(:new).and_return(mock_ctx)
        allow(mock_ctx).to receive(:get_all_versions).and_return([123])
        allow(mock_ctx).to receive(:migrations).and_return([mock_migration])

        result = described_class.send(:ran_migration_names_from_host)
        expect(result).to eq(["CreateUsers"])
      end
    end

    context "when database doesn't exist" do
      it "returns an empty array" do
        mock_paths = double("paths", expanded: ["/fake/path"])
        allow(Rails.application).to receive(:paths).and_return({ "db/migrate" => mock_paths })
        allow(ActiveRecord::MigrationContext).to receive(:new).and_raise(ActiveRecord::NoDatabaseError)

        result = described_class.send(:ran_migration_names_from_host)
        expect(result).to eq([])
      end
    end
  end
end
