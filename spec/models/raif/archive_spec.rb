# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: raif_archives
#
#  id               :bigint           not null, primary key
#  checksum_sha256  :string           not null
#  compressed_bytes :bigint           not null
#  cutoff_at        :datetime         not null
#  key              :string           not null
#  location         :string           not null
#  partition_value  :string
#  record_count     :integer          not null
#  resource_type    :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  first_record_id  :bigint           not null
#  last_record_id   :bigint           not null
#
# Indexes
#
#  index_raif_archives_on_key                                (key) UNIQUE
#  index_raif_archives_on_partition_value                    (partition_value)
#  index_raif_archives_on_resource_type_and_record_id_range  (resource_type,first_record_id,last_record_id)
#
RSpec.describe Raif::Archive, type: :model do
  describe "validations" do
    it "requires the audit fields" do
      archive = described_class.new

      expect(archive).not_to be_valid
      expect(archive.errors.attribute_names).to include(
        :resource_type,
        :key,
        :location,
        :cutoff_at,
        :first_record_id,
        :last_record_id,
        :record_count,
        :compressed_bytes,
        :checksum_sha256
      )
    end

    it "enforces key uniqueness" do
      existing = FB.create(:raif_archive)
      duplicate = FB.build(:raif_archive, key: existing.key)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors.attribute_names).to include(:key)
    end
  end

  describe "partition_value" do
    it "is nullable and round-trips the stored normalized value" do
      unpartitioned = FB.create(:raif_archive)
      partitioned = FB.create(:raif_archive, partition_value: "42")

      expect(unpartitioned.reload.partition_value).to be_nil
      expect(partitioned.reload.partition_value).to eq("42")
    end
  end

  describe ".covering" do
    let!(:archive_a) { FB.create(:raif_archive, first_record_id: 10, last_record_id: 20) }
    let!(:archive_b) { FB.create(:raif_archive, first_record_id: 30, last_record_id: 40) }
    let!(:other_resource_archive) { FB.create(:raif_archive, resource_type: "Document", first_record_id: 10, last_record_id: 40) }

    it "returns the archives whose id range contains the record" do
      expect(described_class.covering(resource_type: "Raif::ModelCompletion", record_id: 15)).to eq([archive_a])
      expect(described_class.covering(resource_type: "Raif::ModelCompletion", record_id: 30)).to eq([archive_b])
      expect(described_class.covering(resource_type: "Raif::ModelCompletion", record_id: 40)).to eq([archive_b])
    end

    it "returns all overlapping archives, newest first" do
      duplicate = FB.create(:raif_archive, first_record_id: 12, last_record_id: 25)

      expect(described_class.covering(resource_type: "Raif::ModelCompletion", record_id: 15)).to eq([duplicate, archive_a])
    end

    it "is empty when no archive covers the record" do
      expect(described_class.covering(resource_type: "Raif::ModelCompletion", record_id: 25)).to be_empty
    end

    it "scopes by resource type" do
      expect(described_class.covering(resource_type: "Document", record_id: 25)).to eq([other_resource_archive])
    end
  end

  describe ".purge_partition!" do
    let(:storage_root) { Dir.mktmpdir }
    let(:storage) { Raif::ArchiveStorage::FileSystem.new(root: storage_root) }

    before do
      # Deliberately purge-hostile config: erasure obligations outlive
      # feature flags, so purging must work with archiving disabled and the
      # partition column unset. Only the storage adapter is required.
      allow(Raif.config).to receive_messages(
        archive_enabled: false,
        archive_partition_column: nil,
        archive_storage: storage
      )
    end

    after { FileUtils.remove_entry(storage_root) }

    def prefix_for(value)
      "raif-archives/partitions/#{Digest::SHA256.hexdigest(value.to_s)}/"
    end

    def write_object(key)
      body = "archived data"
      storage.write(key: key, io: StringIO.new(body), checksum_sha256: Digest::SHA256.hexdigest(body))
    end

    def plant_archive(partition_value, key:)
      write_object(key)
      FB.create(:raif_archive, partition_value: partition_value, key: key)
    end

    it "erases the partition prefix (crash orphans and all resource types included), its rows, and its stamps, leaving others untouched" do
      target_completions = plant_archive("7", key: "#{prefix_for(7)}model-completions/1-100-a.jsonl.gz")
      target_tasks = plant_archive("7", key: "#{prefix_for(7)}tasks/1-50-b.jsonl.gz")
      # Crash orphan: object uploaded, no Raif::Archive row, no discoverable
      # key. Only prefix deletion can erase it.
      write_object("#{prefix_for(7)}model-completions/101-200-orphan.jsonl.gz")

      other = plant_archive("9", key: "#{prefix_for(9)}model-completions/1-100-c.jsonl.gz")
      ungrouped = plant_archive(nil, key: "raif-archives/partitions/_ungrouped/model-completions/1-10-d.jsonl.gz")

      purged_event = FB.create(:raif_inference_cost_event, raif_archive_id: target_completions.id)
      other_event = FB.create(:raif_inference_cost_event, raif_archive_id: other.id)

      # Integer input: normalization must match the stored string value.
      result = described_class.purge_partition!(partition_value: 7)

      expect(Dir.exist?(File.join(storage_root, prefix_for(7)))).to be(false)
      expect(File.exist?(File.join(storage_root, other.key))).to be(true)
      expect(File.exist?(File.join(storage_root, ungrouped.key))).to be(true)

      expect(described_class.exists?(target_completions.id)).to be(false)
      expect(described_class.exists?(target_tasks.id)).to be(false)
      expect(described_class.exists?(other.id)).to be(true)
      expect(described_class.exists?(ungrouped.id)).to be(true)

      # The durable cost events survive; only their archive linkage is
      # severed.
      expect(purged_event.reload.raif_archive_id).to be_nil
      expect(other_event.reload.raif_archive_id).to eq(other.id)

      expect(result[:partition_value]).to eq("7")
      expect(result[:prefix]).to eq(prefix_for(7))
      expect(result[:objects_deleted]).to eq(3)
      expect(result[:archive_rows_deleted]).to eq(2)
      expect(result[:stamps_nullified]).to eq(1)
      expect(result[:duration]).to be_a(Float)
    end

    it "emits the result payload via ActiveSupport::Notifications" do
      plant_archive("7", key: "#{prefix_for(7)}model-completions/1-100-a.jsonl.gz")

      payloads = []
      callback = ->(_name, _start, _finish, _id, payload) { payloads << payload }

      result = ActiveSupport::Notifications.subscribed(callback, "purge_partition.raif") do
        described_class.purge_partition!(partition_value: "7")
      end

      expect(payloads).to eq([result])
    end

    it "rejects values that normalize to blank" do
      expect { described_class.purge_partition!(partition_value: nil) }.to raise_error(ArgumentError, /blank/)
      expect { described_class.purge_partition!(partition_value: "") }.to raise_error(ArgumentError, /blank/)
    end

    it "rejects the UNGROUPED sentinel: the reserved ungrouped partition can never be purged" do
      ungrouped = plant_archive(nil, key: "raif-archives/partitions/_ungrouped/model-completions/1-10-d.jsonl.gz")

      expect do
        described_class.purge_partition!(partition_value: Raif::Archive::UNGROUPED)
      end.to raise_error(ArgumentError, /ungrouped/)

      expect(File.exist?(File.join(storage_root, ungrouped.key))).to be(true)
      expect(described_class.exists?(ungrouped.id)).to be(true)
    end

    it "deletes only rows whose stored value matches the normalized value exactly, even under loose SQL matching" do
      exact = plant_archive("foo", key: "#{prefix_for("foo")}model-completions/1-100-a.jsonl.gz")
      variant = plant_archive("Foo", key: "#{prefix_for("Foo")}model-completions/1-100-b.jsonl.gz")
      exact_event = FB.create(:raif_inference_cost_event, raif_archive_id: exact.id)
      variant_event = FB.create(:raif_inference_cost_event, raif_archive_id: variant.id)

      # Simulate MySQL-style case-insensitive matching, where
      # partition_value = 'foo' also matches 'Foo' (Postgres compares
      # exactly, so the loose match is injected). The case variant is a
      # DIFFERENT partition whose objects live under a different prefix:
      # deleting its rows and stamps would orphan those objects.
      allow(described_class).to receive(:where).and_call_original
      allow(described_class).to receive(:where).with(partition_value: "foo")
        .and_return(described_class.where(id: [exact.id, variant.id]))

      result = described_class.purge_partition!(partition_value: "foo")

      expect(result[:archive_rows_deleted]).to eq(1)
      expect(result[:stamps_nullified]).to eq(1)
      expect(described_class.exists?(exact.id)).to be(false)
      expect(described_class.exists?(variant.id)).to be(true)
      expect(exact_event.reload.raif_archive_id).to be_nil
      expect(variant_event.reload.raif_archive_id).to eq(variant.id)
      expect(File.exist?(File.join(storage_root, variant.key))).to be(true)
    end

    it "never matches ungrouped archives with a real value that normalizes to the string _ungrouped" do
      ungrouped = plant_archive(nil, key: "raif-archives/partitions/_ungrouped/model-completions/1-10-d.jsonl.gz")

      result = described_class.purge_partition!(partition_value: "_ungrouped")

      expect(result[:objects_deleted]).to eq(0)
      expect(result[:archive_rows_deleted]).to eq(0)
      expect(File.exist?(File.join(storage_root, ungrouped.key))).to be(true)
      expect(described_class.exists?(ungrouped.id)).to be(true)
    end

    it "requires a storage adapter implementing delete_prefix" do
      allow(Raif.config).to receive(:archive_storage).and_return(nil)
      expect do
        described_class.purge_partition!(partition_value: "7")
      end.to raise_error(Raif::Errors::InvalidConfigError, /delete_prefix/)

      write_only_adapter = Class.new do
        def write(key:, io:, checksum_sha256:); end
      end.new
      allow(Raif.config).to receive(:archive_storage).and_return(write_only_adapter)
      expect do
        described_class.purge_partition!(partition_value: "7")
      end.to raise_error(Raif::Errors::InvalidConfigError, /delete_prefix/)
    end

    it "raises a retryable busy error when the archive advisory lock is held, deleting nothing" do
      archive = plant_archive("7", key: "#{prefix_for(7)}model-completions/1-100-a.jsonl.gz")

      connection = Raif::ModelCompletion.connection
      allow(connection).to receive(:get_advisory_lock).and_return(false)
      allow(Raif::ModelCompletion).to receive(:connection).and_return(connection)

      expect do
        described_class.purge_partition!(partition_value: "7")
      end.to raise_error(Raif::Errors::ArchiveBusyError, /retry/)

      expect(File.exist?(File.join(storage_root, archive.key))).to be(true)
      expect(described_class.exists?(archive.id)).to be(true)
    end

    it "acquires the same advisory lock id as the archive job" do
      lock_ids = []
      connection = Raif::ModelCompletion.connection
      allow(connection).to receive(:get_advisory_lock).and_wrap_original do |original, lock_id|
        lock_ids << lock_id
        original.call(lock_id)
      end
      allow(Raif::ModelCompletion).to receive(:connection).and_return(connection)

      described_class.purge_partition!(partition_value: "7")

      allow(Raif.config).to receive_messages(archive_enabled: true, model_completion_retention_period: 6.months)
      Raif::ArchiveModelCompletionsJob.new.perform

      expect(lock_ids.size).to eq(2)
      expect(lock_ids.uniq.size).to eq(1)
    end

    it "leaves DB audit state intact when prefix deletion fails" do
      archive = plant_archive("7", key: "#{prefix_for(7)}model-completions/1-100-a.jsonl.gz")
      event = FB.create(:raif_inference_cost_event, raif_archive_id: archive.id)

      allow(storage).to receive(:delete_prefix).and_raise(Raif::Errors::ArchiveStorageError, "prefix deletion exploded")

      expect do
        described_class.purge_partition!(partition_value: "7")
      end.to raise_error(Raif::Errors::ArchiveStorageError)

      expect(described_class.exists?(archive.id)).to be(true)
      expect(event.reload.raif_archive_id).to eq(archive.id)
    end

    it "re-runs cleanly when the DB transaction fails after the prefix was already deleted" do
      archive = plant_archive("7", key: "#{prefix_for(7)}model-completions/1-100-a.jsonl.gz")
      event = FB.create(:raif_inference_cost_event, raif_archive_id: archive.id)

      # Scoped to Raif::Archive relations so a future delete_all on another
      # model cannot be silently mis-targeted.
      attempts = 0
      allow_any_instance_of(ActiveRecord::Relation).to receive(:delete_all).and_wrap_original do |original, *args|
        if original.receiver.klass == Raif::Archive
          attempts += 1
          raise ActiveRecord::StatementInvalid, "db exploded" if attempts == 1
        end

        original.call(*args)
      end

      expect do
        described_class.purge_partition!(partition_value: "7")
      end.to raise_error(ActiveRecord::StatementInvalid)

      # Storage is already erased but the DB rolled back whole: stamps and
      # rows are still intact for the retry.
      expect(File.exist?(File.join(storage_root, archive.key))).to be(false)
      expect(described_class.exists?(archive.id)).to be(true)
      expect(event.reload.raif_archive_id).to eq(archive.id)

      result = described_class.purge_partition!(partition_value: "7")

      expect(result[:objects_deleted]).to eq(0)
      expect(result[:archive_rows_deleted]).to eq(1)
      expect(result[:stamps_nullified]).to eq(1)
      expect(described_class.exists?(archive.id)).to be(false)
      expect(event.reload.raif_archive_id).to be_nil
    end
  end
end
