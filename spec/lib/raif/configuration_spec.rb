# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Configuration do
  describe "#validate!" do
    describe "model_completion_authorizer" do
      around do |example|
        original = Raif.config.model_completion_authorizer
        example.run
      ensure
        Raif.config.model_completion_authorizer = original
      end

      it "allows nil" do
        Raif.config.model_completion_authorizer = nil
        expect { Raif.config.validate! }.to_not raise_error
      end

      it "allows and freezes a callable" do
        authorizer = ->(llm:, source:) {}
        Raif.config.model_completion_authorizer = authorizer

        expect { Raif.config.validate! }.to_not raise_error
        expect(authorizer).to be_frozen
      end

      it "raises for a non-callable value" do
        Raif.config.model_completion_authorizer = "not callable"

        expect { Raif.config.validate! }.to raise_error(
          Raif::Errors::InvalidConfigError,
          /model_completion_authorizer must be nil or respond to :call/
        )
      end
    end

    describe "provider data retention settings" do
      around do |example|
        originals = {
          open_ai_store_responses: Raif.config.open_ai_store_responses,
          open_router_data_collection: Raif.config.open_router_data_collection,
          open_router_zdr: Raif.config.open_router_zdr
        }
        example.run
      ensure
        originals.each { |setting, value| Raif.config.public_send("#{setting}=", value) }
      end

      it "defaults to the restrictive value for each provider" do
        expect(Raif.config.open_ai_store_responses).to be(false)
        expect(Raif.config.open_router_data_collection).to eq("deny")
      end

      # ZDR routes to far fewer endpoints than data_collection filters out, so
      # a restrictive default would turn working models into no-endpoints
      # errors on upgrade.
      it "defaults open_router_zdr to false" do
        expect(Raif.config.open_router_zdr).to be(false)
      end

      it "allows an explicit opt-in" do
        Raif.config.open_ai_store_responses = true
        Raif.config.open_router_data_collection = "allow"
        Raif.config.open_router_zdr = true

        expect { Raif.config.validate! }.to_not raise_error
      end

      it "accepts a symbol for open_router_data_collection" do
        Raif.config.open_router_data_collection = :allow

        expect { Raif.config.validate! }.to_not raise_error
      end

      it "raises when open_ai_store_responses is not a boolean" do
        Raif.config.open_ai_store_responses = nil

        expect { Raif.config.validate! }.to raise_error(
          Raif::Errors::InvalidConfigError,
          /open_ai_store_responses must be true or false/
        )
      end

      it "raises when open_router_zdr is not a boolean" do
        Raif.config.open_router_zdr = "yes"

        expect { Raif.config.validate! }.to raise_error(
          Raif::Errors::InvalidConfigError,
          /open_router_zdr must be true or false/
        )
      end

      it "raises when open_router_data_collection is not allow or deny" do
        Raif.config.open_router_data_collection = "sometimes"

        expect { Raif.config.validate! }.to raise_error(
          Raif::Errors::InvalidConfigError,
          /open_router_data_collection must be one of: allow, deny/
        )
      end
    end

    describe "archive settings" do
      around do |example|
        originals = {
          archive_enabled: Raif.config.archive_enabled,
          archive_storage: Raif.config.archive_storage,
          model_completion_retention_period: Raif.config.model_completion_retention_period,
          task_retention_period: Raif.config.task_retention_period
        }
        example.run
      ensure
        originals.each { |key, value| Raif.config.public_send("#{key}=", value) }
      end

      let(:storage) { Raif::ArchiveStorage::FileSystem.new(root: Dir.mktmpdir) }

      it "defaults to disabled with no storage and no retention period" do
        config = Raif::Configuration.new

        expect(config.archive_enabled).to be(false)
        expect(config.archive_storage).to be_nil
        expect(config.model_completion_retention_period).to be_nil
        expect(config.task_retention_period).to be_nil
      end

      it "allows a valid enabled configuration" do
        Raif.config.archive_enabled = true
        Raif.config.archive_storage = storage
        Raif.config.model_completion_retention_period = 6.months

        expect { Raif.config.validate! }.not_to raise_error
      end

      it "allows enabled with a nil retention period (culling disabled)" do
        Raif.config.archive_enabled = true
        Raif.config.archive_storage = storage
        Raif.config.model_completion_retention_period = nil

        expect { Raif.config.validate! }.not_to raise_error
      end

      it "requires archive_storage when archive_enabled is true" do
        Raif.config.archive_enabled = true
        Raif.config.archive_storage = nil
        Raif.config.model_completion_retention_period = 6.months

        expect { Raif.config.validate! }.to raise_error(
          Raif::Errors::InvalidConfigError,
          /archive_storage is required/
        )
      end

      it "requires the storage adapter to implement write" do
        Raif.config.archive_enabled = true
        Raif.config.archive_storage = Object.new
        Raif.config.model_completion_retention_period = 6.months

        expect { Raif.config.validate! }.to raise_error(
          Raif::Errors::InvalidConfigError,
          /must implement write/
        )
      end

      it "rejects retention periods below 1 month, even when archiving is disabled" do
        Raif.config.archive_enabled = false
        Raif.config.model_completion_retention_period = 3.weeks

        expect { Raif.config.validate! }.to raise_error(
          Raif::Errors::InvalidConfigError,
          /must be at least 1 month/
        )
      end

      it "accepts a retention period of exactly 1 month" do
        Raif.config.archive_enabled = true
        Raif.config.archive_storage = storage
        Raif.config.model_completion_retention_period = 1.month

        expect { Raif.config.validate! }.not_to raise_error
      end

      it "rejects a task retention period below 1 month, even when archiving is disabled" do
        Raif.config.archive_enabled = false
        Raif.config.task_retention_period = 3.weeks

        expect { Raif.config.validate! }.to raise_error(
          Raif::Errors::InvalidConfigError,
          /task_retention_period must be at least 1 month/
        )
      end

      it "accepts a task retention period of exactly 1 month" do
        Raif.config.archive_enabled = true
        Raif.config.archive_storage = storage
        Raif.config.task_retention_period = 1.month

        expect { Raif.config.validate! }.not_to raise_error
      end

      it "validates archive settings even when no LLMs are registered" do
        # validate! returns early (with a console notice) when the LLM
        # registry is empty; archive validation guards a destructive path
        # and must run before that early return.
        allow(Raif).to receive(:llm_registry).and_return({})
        Raif.config.model_completion_retention_period = 1.day

        expect { Raif.config.validate! }.to raise_error(
          Raif::Errors::InvalidConfigError,
          /must be at least 1 month/
        )
      end
    end

    describe "archive partitioning settings" do
      around do |example|
        originals = {
          archive_partition_column: Raif.config.archive_partition_column,
          archive_partition_fallback: Raif.config.archive_partition_fallback
        }
        example.run
      ensure
        originals.each { |key, value| Raif.config.public_send("#{key}=", value) }
      end

      it "defaults both partitioning options to nil" do
        config = Raif::Configuration.new

        expect(config.archive_partition_column).to be_nil
        expect(config.archive_partition_fallback).to be_nil
      end

      it "allows a symbol partition column" do
        Raif.config.archive_partition_column = :account_id

        expect { Raif.config.validate! }.not_to raise_error
      end

      it "does not check the partition column against the database at boot" do
        # Column existence is validated lazily when the archive job or
        # dry_run executes; boot validation must stay usable on a blank
        # database (db:create, db:migrate, asset precompilation).
        Raif.config.archive_partition_column = :column_that_does_not_exist

        expect { Raif.config.validate! }.not_to raise_error
      end

      it "rejects a non-symbol partition column" do
        Raif.config.archive_partition_column = "account_id"

        expect { Raif.config.validate! }.to raise_error(
          Raif::Errors::InvalidConfigError,
          /archive_partition_column must be a Symbol/
        )
      end

      it "allows the UNGROUPED sentinel as the partition fallback" do
        Raif.config.archive_partition_column = :account_id
        Raif.config.archive_partition_fallback = Raif::ArchivePartition::UNGROUPED

        expect { Raif.config.validate! }.not_to raise_error
      end

      it "accepts the sentinel via its Raif::Archive::UNGROUPED alias" do
        Raif.config.archive_partition_column = :account_id
        Raif.config.archive_partition_fallback = Raif::Archive::UNGROUPED

        expect { Raif.config.validate! }.not_to raise_error
      end

      it "rejects any fallback other than nil or the UNGROUPED sentinel" do
        Raif.config.archive_partition_column = :account_id
        Raif.config.archive_partition_fallback = "_ungrouped"

        expect { Raif.config.validate! }.to raise_error(
          Raif::Errors::InvalidConfigError,
          /archive_partition_fallback must be nil \(fail closed\) or Raif::ArchivePartition::UNGROUPED/
        )
      end
    end
  end
end
