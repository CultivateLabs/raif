# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::EvalsDatabase do
  # Rails merges DATABASE_URL into the current environment's primary config, which CI sets, so it
  # would replace the database each example names.
  def build_configurations(configurations)
    database_url = ENV.delete("DATABASE_URL")
    ActiveRecord::DatabaseConfigurations.new(configurations)
  ensure
    ENV["DATABASE_URL"] = database_url if database_url
  end

  describe ".name_for" do
    {
      "app_test" => "app_raif_evals",
      "app_development" => "app_development_raif_evals",
      "app_test_shard" => "app_test_shard_raif_evals",
      "db/test.sqlite3" => "db/test_raif_evals.sqlite3",
      "storage/app_test.sqlite3" => "storage/app_raif_evals.sqlite3",
      "file:db/test.sqlite3?mode=rwc" => "file:db/test_raif_evals.sqlite3?mode=rwc",
      "file:db/test.sqlite3" => "file:db/test_raif_evals.sqlite3",
      ":memory:" => ":memory:",
      "file::memory:?mode=memory&cache=shared" => "file::memory:?mode=memory&cache=shared"
    }.each do |database, expected|
      it "names #{database} #{expected}" do
        expect(described_class.name_for(database, suffix: "_raif_evals")).to eq(expected)
      end
    end
  end

  describe ".name_for a worker database" do
    {
      "app_raif_evals" => "app_raif_evals_2",
      "app_test" => "app_test_2",
      "db/test_raif_evals.sqlite3" => "db/test_raif_evals_2.sqlite3",
      "file:db/test_raif_evals.sqlite3?mode=rwc" => "file:db/test_raif_evals_2.sqlite3?mode=rwc",
      ":memory:" => ":memory:"
    }.each do |database, expected|
      it "names #{database} #{expected}" do
        expect(described_class.name_for(database, suffix: "_2", replacing: nil)).to eq(expected)
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

      expect(described_class).to have_received(:switch_to).with("_raif_evals", replacing: "_test", lock: true)
    end

    it "does nothing outside an eval run" do
      allow(described_class).to receive(:enabled?).and_return(false)
      allow(described_class).to receive(:switch_to)

      described_class.configure!

      expect(described_class).not_to have_received(:switch_to)
    end
  end

  describe ".use_worker_database!" do
    it "renames the databases, drops the inherited connections, then prepares the worker's database" do
      allow(described_class).to receive(:rename)
      allow(ActiveRecord::Base.connection_handler).to receive(:clear_all_connections!)
      allow(described_class).to receive(:prepare!)

      described_class.use_worker_database!(3)

      expect(described_class).to have_received(:rename)
        .with(ActiveRecord::Base.configurations, env_name: "test", suffix: "_3", replacing: nil).ordered
      expect(ActiveRecord::Base.connection_handler).to have_received(:clear_all_connections!).with(:all).ordered
      expect(described_class).to have_received(:prepare!).ordered
    end
  end

  describe ".rename" do
    let(:configurations) do
      build_configurations(
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

  describe ".lock!" do
    let(:root) { Pathname.new(Dir.mktmpdir) }

    before do
      allow(Rails).to receive(:root).and_return(root)
      allow(described_class).to receive(:database_names).and_return(["app_raif_evals"])
    end

    after do
      described_class.instance_variable_get(:@lock_file)&.close
      described_class.instance_variable_set(:@lock_file, nil)
      FileUtils.rm_rf(root)
    end

    it "refuses a second run on the same evals database" do
      described_class.lock!

      expect { described_class.lock! }.to raise_error(Raif::EvalsDatabase::InUseError, /app_raif_evals/)
    end

    it "lets a run start once the one before it has finished" do
      described_class.lock!
      described_class.instance_variable_get(:@lock_file).close

      expect { described_class.lock! }.not_to raise_error
    end

    it "does not lock an in-memory database, which no other run can reach" do
      allow(described_class).to receive(:database_names).and_return([":memory:"])

      described_class.lock!

      expect { described_class.lock! }.not_to raise_error
    end
  end

  describe ".prepare!" do
    let(:reporting_schema_dump) { { "schema_dump" => "schema.rb" } }
    let(:configurations) do
      build_configurations(
        "test" => {
          "primary_replica" => { "adapter" => "postgresql", "database" => "app_raif_evals", "replica" => true },
          "primary" => { "adapter" => "postgresql", "database" => "app_raif_evals" },
          "reporting_replica" => {
            "adapter" => "postgresql",
            "database" => "reporting_replica_raif_evals",
            "replica" => true
          }.merge(reporting_schema_dump),
          "warehouse" => { "adapter" => "postgresql", "database" => "warehouse", "database_tasks" => false }
        }
      )
    end

    let(:prepared) { [] }

    before do
      allow(ActiveRecord::Base).to receive(:configurations).and_return(configurations)
      allow(ActiveRecord::Base).to receive(:establish_connection)
      allow(ActiveRecord::Tasks::DatabaseTasks).to receive(:reconstruct_from_schema) { |db_config, *| prepared << db_config.name }
    end

    it "prepares each managed database once, from its writer when a replica shares it" do
      described_class.prepare!

      expect(prepared).to eq(["primary", "reporting_replica"])
    end

    context "when a replica with a database of its own has no schema file" do
      let(:reporting_schema_dump) { {} }

      it "refuses it rather than let Rails advise a migration" do
        expect { described_class.prepare! }.to raise_error(Raif::Errors::InvalidConfigError, /reporting_replica replica/)
      end
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
