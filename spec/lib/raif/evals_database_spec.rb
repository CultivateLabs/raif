# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::EvalsDatabase do
  describe ".name_for" do
    {
      "app_test" => "app_raif_evals",
      "app_development" => "app_development_raif_evals",
      "app_test_shard" => "app_test_shard_raif_evals",
      "db/test.sqlite3" => "db/test_raif_evals.sqlite3",
      "storage/app_test.sqlite3" => "storage/app_raif_evals.sqlite3",
      ":memory:" => ":memory:",
      "file::memory:?mode=memory&cache=shared" => "file::memory:?mode=memory&cache=shared"
    }.each do |database, expected|
      it "names #{database} #{expected}" do
        expect(described_class.name_for(database, suffix: "_raif_evals")).to eq(expected)
      end
    end
  end

  describe ".configure!" do
    # Boot goes on to query the renamed database - routes load after after_initialize - so a
    # database created later would not exist yet when it does.
    it "prepares the evals database in the same hook that renames it" do
      allow(described_class).to receive(:enabled?).and_return(true)
      allow(described_class).to receive(:switch_to)

      described_class.configure!

      expect(described_class).to have_received(:switch_to).with("_raif_evals")
    end

    it "does nothing outside an eval run" do
      allow(described_class).to receive(:enabled?).and_return(false)
      allow(described_class).to receive(:switch_to)

      described_class.configure!

      expect(described_class).not_to have_received(:switch_to)
    end
  end

  describe ".rename" do
    let(:configurations) do
      ActiveRecord::DatabaseConfigurations.new(
        "test" => {
          "primary" => { "adapter" => "postgresql", "database" => "app_test" },
          "primary_replica" => { "adapter" => "postgresql", "database" => "app_test", "replica" => true },
          "animals" => { "adapter" => "postgresql", "database" => "animals_test" },
          "warehouse" => { "adapter" => "postgresql", "database" => "warehouse", "database_tasks" => false }
        },
        "development" => { "adapter" => "postgresql", "database" => "app_development" }
      )
    end

    def database_for(env_name, name)
      configurations.configs_for(env_name: env_name, name: name, include_hidden: true).database
    end

    before { described_class.rename(configurations, env_name: "test", suffix: "_raif_evals") }

    it "renames every managed database in the environment, replicas included" do
      expect(database_for("test", "primary")).to eq("app_raif_evals")
      expect(database_for("test", "primary_replica")).to eq("app_raif_evals")
      expect(database_for("test", "animals")).to eq("animals_raif_evals")
    end

    it "leaves a database the host does not manage alone" do
      expect(database_for("test", "warehouse")).to eq("warehouse")
    end

    it "leaves other environments alone" do
      expect(database_for("development", "primary")).to eq("app_development")
    end
  end

  describe ".enabled?" do
    around do |example|
      original = ENV.fetch("RAIF_RUNNING_EVALS", nil)
      example.run
      original.nil? ? ENV.delete("RAIF_RUNNING_EVALS") : ENV["RAIF_RUNNING_EVALS"] = original
    end

    it "is enabled for an eval run in the test environment" do
      ENV["RAIF_RUNNING_EVALS"] = "true"

      expect(described_class).to be_enabled
    end

    it "is disabled outside an eval run, so the test suite keeps the test database" do
      ENV.delete("RAIF_RUNNING_EVALS")

      expect(described_class).not_to be_enabled
    end

    it "is disabled outside the test environment" do
      ENV["RAIF_RUNNING_EVALS"] = "true"
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("development"))

      expect(described_class).not_to be_enabled
    end

    it "is disabled when the suffix is unset" do
      ENV["RAIF_RUNNING_EVALS"] = "true"
      allow(Raif.config).to receive(:evals_database_suffix).and_return(nil)

      expect(described_class).not_to be_enabled
    end
  end

  describe "config validation" do
    it "rejects a blank suffix" do
      config = Raif::Configuration.new
      config.evals_database_suffix = ""

      expect { config.validate! }.to raise_error(Raif::Errors::InvalidConfigError, /evals_database_suffix/)
    end
  end
end
