# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::ArchiveModelCompletionsJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:storage_root) { Dir.mktmpdir }
  let(:storage) { Raif::ArchiveStorage::FileSystem.new(root: storage_root) }
  let(:retention_period) { 6.months }

  before do
    allow(Raif.config).to receive_messages(
      archive_enabled: true,
      archive_storage: storage,
      model_completion_retention_period: retention_period
    )
  end

  after { FileUtils.remove_entry(storage_root) }

  def create_terminal_completion(created_at: 8.months.ago, **attrs)
    completion = FB.create(:raif_model_completion, llm_model_key: "raif_test_llm", model_api_name: "raif-test-llm", **attrs)
    completion.completed!
    completion.update_columns(created_at: created_at, updated_at: created_at)
    completion
  end

  def perform(**kwargs)
    described_class.new.perform(**kwargs)
  end

  def read_archived_lines(archive)
    Zlib::GzipReader.open(File.join(storage_root, archive.key)) { |gz| gz.read.split("\n") }
  end

  describe "disabled by default" do
    let!(:old_completion) { create_terminal_completion }

    it "no-ops when archive_enabled is false" do
      allow(Raif.config).to receive(:archive_enabled).and_return(false)

      expect { perform }.not_to change { [Raif::Archive.count, Raif::ModelCompletion.count] }
    end

    it "no-ops when no storage adapter is configured" do
      allow(Raif.config).to receive(:archive_storage).and_return(nil)

      expect { perform }.not_to change { [Raif::Archive.count, Raif::ModelCompletion.count] }
    end

    it "no-ops when the retention period is nil" do
      allow(Raif.config).to receive(:model_completion_retention_period).and_return(nil)

      expect { perform }.not_to change { [Raif::Archive.count, Raif::ModelCompletion.count] }
    end

    it "refuses to run with a retention period under the 1 month floor, even if boot validation was skipped" do
      allow(Raif.config).to receive(:model_completion_retention_period).and_return(3.days)

      expect { perform }.to raise_error(Raif::Errors::InvalidConfigError, /must be at least 1 month/)
      expect(Raif::ModelCompletion.exists?(old_completion.id)).to be(true)
      expect(Raif::Archive.count).to eq(0)
    end
  end

  describe "happy path" do
    let!(:old_completions) { 3.times.map { create_terminal_completion } }
    let!(:recent_completion) { create_terminal_completion(created_at: 1.month.ago) }
    let!(:active_completion) do
      completion = create_terminal_completion
      completion.update_columns(updated_at: 1.hour.ago)
      completion
    end

    it "archives and deletes old completions, leaving recent and non-quiescent rows untouched" do
      perform

      expect(Raif::ModelCompletion.where(id: old_completions.map(&:id))).to be_empty
      expect(Raif::ModelCompletion.exists?(recent_completion.id)).to be(true)
      expect(Raif::ModelCompletion.exists?(active_completion.id)).to be(true)

      archive = Raif::Archive.sole
      expect(archive.resource_type).to eq("Raif::ModelCompletion")
      expect(archive.partition_value).to be_nil
      expect(archive.record_count).to eq(3)
      expect(archive.first_record_id).to eq(old_completions.map(&:id).min)
      expect(archive.last_record_id).to eq(old_completions.map(&:id).max)
      # 122-bit UUID run suffix: key reuse must be effectively impossible,
      # since a colliding key would overwrite a prior archive object.
      uuid = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/
      expect(archive.key)
        .to match(%r{\Araif-archives/model-completions/#{archive.first_record_id}-#{archive.last_record_id}-\d{8}T\d{6}Z-#{uuid}\.jsonl\.gz\z})
      expect(archive.location).to eq(File.join(storage_root, archive.key))
      expect(archive.cutoff_at).to be_within(1.minute).of(retention_period.ago)
      expect(archive.checksum_sha256).to eq(Digest::SHA256.file(archive.location).hexdigest)
      expect(archive.compressed_bytes).to eq(File.size(archive.location))

      lines = read_archived_lines(archive)
      manifest = JSON.parse(lines.first)
      expect(manifest["manifest_version"]).to eq(1)
      expect(manifest["resource_type"]).to eq("Raif::ModelCompletion")
      expect(manifest["record_count"]).to eq(3)
      expect(lines.drop(1).map { |l| JSON.parse(l)["id"] }).to match_array(old_completions.map(&:id))
    end

    it "leaves rows at the exact cutoff boundary untouched" do
      freeze_time do
        boundary_completion = create_terminal_completion(created_at: retention_period.ago)

        perform

        expect(Raif::ModelCompletion.exists?(boundary_completion.id)).to be(true)
      end
    end

    it "nullifies the cost event FK, keeps the correlation id, stamps the archive, and flips model_completion_live?" do
      completion = old_completions.first
      event = completion.raif_inference_cost_event
      expect(event.model_completion_live?).to be(true)

      perform

      archive = Raif::Archive.sole
      event.reload
      expect(event.raif_model_completion_id).to be_nil
      expect(event.original_model_completion_id).to eq(completion.id)
      expect(event.raif_archive_id).to eq(archive.id)
      expect(event.model_completion_live?).to be(false)
      expect(event.raif_archive).to eq(archive)
      expect(Raif::Archive.covering(resource_type: "Raif::ModelCompletion", record_id: completion.id)).to eq([archive])
    end
  end

  describe "eligibility guards" do
    it "never culls a terminal completion whose cost event is missing, even inside the archived id range" do
      completions = 3.times.map { create_terminal_completion }
      protected_completion = completions[1]
      protected_completion.raif_inference_cost_event.destroy!

      perform

      expect(Raif::ModelCompletion.exists?(protected_completion.id)).to be(true)

      archive = Raif::Archive.sole
      expect(archive.record_count).to eq(2)
      expect(archive.first_record_id).to be < protected_completion.id
      expect(archive.last_record_id).to be > protected_completion.id

      archived_ids = read_archived_lines(archive).drop(1).map { |l| JSON.parse(l)["id"] }
      expect(archived_ids).not_to include(protected_completion.id)
    end

    it "never culls a terminal completion whose cost event is stale, until repair re-syncs it" do
      completion = create_terminal_completion
      event = completion.raif_inference_cost_event
      event.update_columns(updated_at: completion.updated_at - 1.day)

      perform

      expect(Raif::ModelCompletion.exists?(completion.id)).to be(true)
      expect(Raif::Archive.count).to eq(0)

      # The widened repair scope re-syncs (or freshness-certifies) the stale
      # event, making the row eligible again.
      Raif::InferenceCostEvent.backfill!
      expect(event.reload.updated_at).to be >= completion.reload.updated_at

      perform

      expect(Raif::ModelCompletion.exists?(completion.id)).to be(false)
      expect(event.reload.raif_archive_id).to eq(Raif::Archive.sole.id)
    end

    it "never culls a completion with citations its conversation entry has not copied" do
      creator = FB.create(:raif_test_user)
      conversation = FB.create(:raif_test_conversation, creator: creator)
      entry = FB.create(:raif_conversation_entry, raif_conversation: conversation, creator: creator)
      protected_completion = create_terminal_completion(source: entry, citations: [{ "url" => "https://example.com" }])

      perform

      expect(Raif::ModelCompletion.exists?(protected_completion.id)).to be(true)
      expect(Raif::Archive.count).to eq(0)
    end

    it "culls a completion with citations once its conversation entry has copied them" do
      creator = FB.create(:raif_test_user)
      conversation = FB.create(:raif_test_conversation, creator: creator)
      entry = FB.create(:raif_conversation_entry, raif_conversation: conversation, creator: creator)
      entry.update_columns(citations: [{ "url" => "https://example.com" }])
      completion = create_terminal_completion(source: entry, citations: [{ "url" => "https://example.com" }])

      perform

      expect(Raif::ModelCompletion.exists?(completion.id)).to be(false)
      expect(Raif::Archive.count).to eq(1)
    end

    it "never culls a member of a non-terminal model completion batch" do
      batch = FB.create(:raif_model_completion_batch_anthropic, status: "in_progress")
      protected_completion = create_terminal_completion(raif_model_completion_batch: batch)
      create_terminal_completion

      perform

      expect(Raif::ModelCompletion.exists?(protected_completion.id)).to be(true)
    end

    it "archives and culls nonterminal rows, which have no cost event to require" do
      zombie = FB.create(:raif_model_completion, llm_model_key: "raif_test_llm", model_api_name: "raif-test-llm")
      zombie.update_columns(created_at: 8.months.ago, updated_at: 8.months.ago)

      perform

      expect(Raif::ModelCompletion.exists?(zombie.id)).to be(false)
      expect(Raif::Archive.count).to eq(1)
      expect(Raif::Archive.last.record_count).to eq(1)
    end
  end

  describe "invariant: a batch is deleted only after this run uploaded it" do
    let!(:old_completions) { 2.times.map { create_terminal_completion } }

    it "deletes zero rows and records zero archives when the adapter write fails" do
      allow(storage).to receive(:write).and_raise(IOError, "upload exploded")

      expect { perform }.to raise_error(IOError)

      expect(Raif::ModelCompletion.count).to eq(2)
      expect(Raif::Archive.count).to eq(0)
      expect(Raif::InferenceCostEvent.where.not(raif_archive_id: nil).count).to eq(0)
    end

    it "deletes zero rows and records zero archives when the adapter returns a blank location instead of raising" do
      allow(storage).to receive(:write).and_return(nil)

      expect { perform }.to raise_error(Raif::Errors::ArchiveStorageError, /nonblank location string/)

      expect(Raif::ModelCompletion.count).to eq(2)
      expect(Raif::Archive.count).to eq(0)
      expect(Raif::InferenceCostEvent.where.not(raif_archive_id: nil).count).to eq(0)
    end
  end

  describe "atomic cull transaction" do
    let!(:old_completions) { 2.times.map { create_terminal_completion } }

    it "rolls back the event stamps when deletion fails, leaving the upload as an accounted-for duplicate" do
      allow_any_instance_of(ActiveRecord::Batches::BatchEnumerator)
        .to receive(:delete_all)
        .and_raise(ActiveRecord::StatementInvalid, "delete exploded")

      expect { perform }.to raise_error(ActiveRecord::StatementInvalid)

      # Stamps and deletes roll back together: no event may claim its
      # completion was culled into an archive while the row still exists.
      expect(Raif::ModelCompletion.count).to eq(2)
      expect(Raif::InferenceCostEvent.where.not(raif_archive_id: nil).count).to eq(0)

      # The Archive row records the upload and stays; the next run archives
      # the rows again under a new key (harmless duplicate).
      expect(Raif::Archive.count).to eq(1)
    end

    it "rolls back the cull when a cost event vanishes between selection and stamping" do
      event = old_completions.first.raif_inference_cost_event

      # The row locks cover completions, not events: simulate an external
      # writer deleting an event in the window between the locked selection
      # and the stamp.
      allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all).and_wrap_original do |original, *args|
        event.delete
        original.call(*args)
      end

      expect { perform }.to raise_error(/vanished between eligibility selection and stamping/)

      expect(Raif::ModelCompletion.count).to eq(2)
      expect(Raif::InferenceCostEvent.where.not(raif_archive_id: nil).count).to eq(0)
      expect(Raif::Archive.count).to eq(1)
    end

    it "locks the final selection so nothing can change between the re-check and the delete" do
      queries = []
      callback = ->(*_args, payload) { queries << payload[:sql] }

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { perform }

      expect(queries).to include(match(/raif_model_completions.*FOR UPDATE/m))
      expect(Raif::ModelCompletion.count).to eq(0)
    end
  end

  describe "invariant: keys are never reused across runs" do
    let!(:old_completions) { 2.times.map { create_terminal_completion } }

    it "re-archives under a new key after a crash between upload and delete, leaving a harmless duplicate" do
      # Simulate a crash after the upload + Raif::Archive row + stamping, but
      # before any rows were deleted.
      delete_attempts = 0
      allow_any_instance_of(ActiveRecord::Batches::BatchEnumerator).to receive(:delete_all).and_wrap_original do |original, *args|
        delete_attempts += 1
        raise Interrupt if delete_attempts == 1

        original.call(*args)
      end

      expect { perform }.to raise_error(Interrupt)

      expect(Raif::Archive.count).to eq(1)
      expect(Raif::ModelCompletion.count).to eq(2)

      perform

      first_archive, second_archive = Raif::Archive.order(:id).to_a
      expect(Raif::Archive.count).to eq(2)
      expect(second_archive.key).not_to eq(first_archive.key)
      expect(Raif::ModelCompletion.count).to eq(0)

      # Both objects exist in storage; the older one is a harmless duplicate.
      expect(File.exist?(File.join(storage_root, first_archive.key))).to be(true)
      expect(File.exist?(File.join(storage_root, second_archive.key))).to be(true)

      # covering returns both overlapping archives, newest first; the stamp
      # points at the run that actually deleted the rows.
      covering = Raif::Archive.covering(resource_type: "Raif::ModelCompletion", record_id: old_completions.first.id)
      expect(covering).to eq([second_archive, first_archive])
      expect(Raif::InferenceCostEvent.pluck(:raif_archive_id).uniq).to eq([second_archive.id])
    end
  end

  describe "invariant: eligibility is re-checked at delete time" do
    it "retains (and leaves unstamped) a completion mutated during the upload window" do
      completions = 2.times.map { create_terminal_completion }
      mutated, untouched = completions

      # An application writer touches the row mid-upload (the PUT of a large
      # batch can take minutes): its uploaded copy is stale, so it must
      # survive the delete and stay unstamped.
      allow(storage).to receive(:write).and_wrap_original do |original, **kwargs|
        mutated.update_columns(updated_at: Time.current)
        original.call(**kwargs)
      end

      perform

      archive = Raif::Archive.sole
      expect(Raif::ModelCompletion.exists?(mutated.id)).to be(true)
      expect(Raif::ModelCompletion.exists?(untouched.id)).to be(false)

      # The uploaded object still contains the stale copy - the accepted
      # harmless duplicate; the row re-enters a later batch once quiescent.
      archived_ids = read_archived_lines(archive).drop(1).map { |l| JSON.parse(l)["id"] }
      expect(archived_ids).to match_array(completions.map(&:id))

      # The stamp means "culled into this archive": only the deleted row's
      # event carries it.
      expect(mutated.raif_inference_cost_event.reload.raif_archive_id).to be_nil
      expect(untouched.raif_inference_cost_event.reload.raif_archive_id).to eq(archive.id)
    end
  end

  describe "batching" do
    it "closes a batch early at the uncompressed byte cap; leftovers re-enter the next batch" do
      stub_const("Raif::ArchiveModelCompletionsJob::BATCH_UNCOMPRESSED_BYTE_LIMIT", 1)

      completions = 2.times.map { create_terminal_completion }

      perform

      archives = Raif::Archive.order(:id).to_a
      expect(archives.size).to eq(2)
      expect(archives.map(&:record_count)).to eq([1, 1])
      expect(Raif::ModelCompletion.where(id: completions.map(&:id))).to be_empty

      # Each archive's manifest, id range, and stamped events cover exactly
      # the single record actually written to it.
      archives.each do |archive|
        manifest = JSON.parse(read_archived_lines(archive).first)
        expect(manifest["record_count"]).to eq(1)
        expect(archive.first_record_id).to eq(archive.last_record_id)
        expect(Raif::InferenceCostEvent.where(raif_archive_id: archive.id).count).to eq(1)
      end
    end

    it "respects max_objects, processing oldest completions first" do
      stub_const("Raif::ArchiveModelCompletionsJob::BATCH_RECORD_LIMIT", 1)

      oldest = create_terminal_completion(created_at: 10.months.ago)
      middle = create_terminal_completion(created_at: 9.months.ago)
      newest = create_terminal_completion(created_at: 8.months.ago)

      perform(max_objects: 2)

      expect(Raif::Archive.count).to eq(2)
      expect(Raif::ModelCompletion.exists?(oldest.id)).to be(false)
      expect(Raif::ModelCompletion.exists?(middle.id)).to be(false)
      expect(Raif::ModelCompletion.exists?(newest.id)).to be(true)
    end

    it "treats max_records as a hard ceiling, capping the final object short" do
      3.times.map { create_terminal_completion }

      perform(max_records: 2)

      archive = Raif::Archive.sole
      expect(archive.record_count).to eq(2)
      expect(Raif::ModelCompletion.count).to eq(1)
    end

    it "stops safely between objects once max_runtime has elapsed" do
      create_terminal_completion

      perform(max_runtime: 0.seconds)

      expect(Raif::Archive.count).to eq(0)
      expect(Raif::ModelCompletion.count).to eq(1)
    end

    it "stops between objects when max_runtime elapses mid-run, finishing the object it started" do
      stub_const("Raif::ArchiveModelCompletionsJob::BATCH_RECORD_LIMIT", 1)

      first = create_terminal_completion(created_at: 10.months.ago)
      second = create_terminal_completion(created_at: 9.months.ago)

      # Deadline is monotonic_now + 10 at job start (0); the pre-object
      # check sees 1 (under deadline, first object proceeds), every check
      # after that sees 11 (past deadline, run stops).
      allow_any_instance_of(described_class).to receive(:monotonic_now).and_return(0, 1, 11)

      perform(max_runtime: 10.seconds)

      expect(Raif::Archive.count).to eq(1)
      expect(Raif::ModelCompletion.exists?(first.id)).to be(false)
      expect(Raif::ModelCompletion.exists?(second.id)).to be(true)
      expect(second.raif_inference_cost_event.reload.raif_archive_id).to be_nil
    end

    it "pins the per-object safety caps: a silent change must be deliberate" do
      expect(described_class::BATCH_RECORD_LIMIT).to eq(25_000)
      expect(described_class::BATCH_UNCOMPRESSED_BYTE_LIMIT).to eq(512.megabytes)
    end
  end

  describe "partitioning" do
    before do
      allow(Raif.config).to receive_messages(archive_partition_column: :source_id, archive_partition_fallback: nil)
    end

    # source_id stands in for a host partition column (e.g. account_id):
    # a plain nullable bigint on raif_model_completions.
    def create_partitioned_completion(partition_value, **attrs)
      completion = create_terminal_completion(**attrs)
      completion.update_columns(source_id: partition_value)
      completion
    end

    def partition_prefix(value)
      "raif-archives/partitions/#{Digest::SHA256.hexdigest(value.to_s)}/model-completions/"
    end

    it "archives each partition into its own object, manifest, and audit row" do
      a1 = create_partitioned_completion(7)
      a2 = create_partitioned_completion(7)
      b1 = create_partitioned_completion(9)

      perform

      expect(Raif::ModelCompletion.count).to eq(0)
      archives = Raif::Archive.order(:id).to_a
      expect(archives.size).to eq(2)

      archive_a = archives.find { |archive| archive.partition_value == "7" }
      archive_b = archives.find { |archive| archive.partition_value == "9" }

      expect(archive_a.key).to start_with(partition_prefix(7))
      expect(archive_a.record_count).to eq(2)
      lines_a = read_archived_lines(archive_a)
      manifest_a = JSON.parse(lines_a.first)
      expect(manifest_a["partition_column"]).to eq("source_id")
      expect(manifest_a["partition_value"]).to eq("7")
      expect(lines_a.drop(1).map { |l| JSON.parse(l)["id"] }).to match_array([a1.id, a2.id])

      expect(archive_b.key).to start_with(partition_prefix(9))
      expect(archive_b.record_count).to eq(1)
      lines_b = read_archived_lines(archive_b)
      expect(JSON.parse(lines_b.first)["partition_value"]).to eq("9")
      expect(lines_b.drop(1).map { |l| JSON.parse(l)["id"] }).to eq([b1.id])

      # Every cost event stamp points at the archive of its own partition.
      expect(a1.raif_inference_cost_event.reload.raif_archive_id).to eq(archive_a.id)
      expect(a2.raif_inference_cost_event.reload.raif_archive_id).to eq(archive_a.id)
      expect(b1.raif_inference_cost_event.reload.raif_archive_id).to eq(archive_b.id)
    end

    it "fails closed on records with a NULL partition value: retained, never archived" do
      orphan = create_partitioned_completion(nil)
      partitioned = create_partitioned_completion(7)

      perform

      expect(Raif::ModelCompletion.exists?(orphan.id)).to be(true)
      expect(Raif::ModelCompletion.exists?(partitioned.id)).to be(false)

      archive = Raif::Archive.sole
      expect(archive.partition_value).to eq("7")
      archived_ids = read_archived_lines(archive).drop(1).map { |l| JSON.parse(l)["id"] }
      expect(archived_ids).to eq([partitioned.id])
    end

    it "archives NULL-partition records under the reserved _ungrouped segment when the fallback is UNGROUPED" do
      allow(Raif.config).to receive(:archive_partition_fallback).and_return(Raif::Archive::UNGROUPED)
      orphan = create_partitioned_completion(nil)

      perform

      expect(Raif::ModelCompletion.exists?(orphan.id)).to be(false)

      archive = Raif::Archive.sole
      expect(archive.partition_value).to be_nil
      expect(archive.key).to start_with("raif-archives/partitions/_ungrouped/model-completions/")

      manifest = JSON.parse(read_archived_lines(archive).first)
      expect(manifest["partition_column"]).to eq("source_id")
      expect(manifest["partition_value"]).to be_nil
    end

    it "round-robins passes so a large-backlog partition cannot monopolize a bounded run" do
      stub_const("Raif::ArchiveModelCompletionsJob::BATCH_RECORD_LIMIT", 1)

      backlog_oldest = create_partitioned_completion(7, created_at: 10.months.ago)
      backlog_next = create_partitioned_completion(7, created_at: 9.months.ago)
      small_partition = create_partitioned_completion(9, created_at: 8.months.ago)

      perform(max_objects: 2)

      # Strict global oldest-first would spend both objects on partition 7.
      expect(Raif::ModelCompletion.exists?(backlog_oldest.id)).to be(false)
      expect(Raif::ModelCompletion.exists?(small_partition.id)).to be(false)
      expect(Raif::ModelCompletion.exists?(backlog_next.id)).to be(true)
    end

    it "closes partitioned objects early at the byte cap; leftovers re-enter on a later pass" do
      stub_const("Raif::ArchiveModelCompletionsJob::BATCH_UNCOMPRESSED_BYTE_LIMIT", 1)

      completions = 2.times.map { create_partitioned_completion(7) }

      perform

      archives = Raif::Archive.order(:id).to_a
      expect(archives.size).to eq(2)
      expect(archives.map(&:record_count)).to eq([1, 1])
      expect(archives.map(&:partition_value).uniq).to eq(["7"])
      archives.each { |archive| expect(archive.key).to start_with(partition_prefix(7)) }
      expect(Raif::ModelCompletion.where(id: completions.map(&:id))).to be_empty
    end

    it "drains many small partitions within a single run" do
      completions = [1, 2, 3].map { |value| create_partitioned_completion(value) }

      perform

      expect(Raif::ModelCompletion.count).to eq(0)
      expect(Raif::Archive.count).to eq(3)
      expect(Raif::Archive.pluck(:partition_value)).to match_array(["1", "2", "3"])
      expect(completions.map { |c| c.raif_inference_cost_event.reload.raif_archive_id }.uniq.size).to eq(3)
    end

    it "aborts the cull and cleans up the tainted object when a record's partition changes during upload" do
      completion = create_partitioned_completion(7)

      mutated = false
      allow(storage).to receive(:write).and_wrap_original do |original, **kwargs|
        unless mutated
          mutated = true
          completion.update_columns(source_id: 8)
        end
        original.call(**kwargs)
      end

      expect { perform }.not_to raise_error

      # The whole cull rolled back: the row survives with no stamp, and the
      # tainted object and its audit row were both removed.
      expect(Raif::ModelCompletion.exists?(completion.id)).to be(true)
      expect(completion.raif_inference_cost_event.reload.raif_archive_id).to be_nil
      expect(Raif::Archive.count).to eq(0)
      expect(Dir.glob(File.join(storage_root, "**", "*")).select { |f| File.file?(f) }).to be_empty

      # The record now archives cleanly under its new partition on a later run.
      perform

      archive = Raif::Archive.sole
      expect(archive.partition_value).to eq("8")
      expect(archive.key).to start_with(partition_prefix(8))
      expect(Raif::ModelCompletion.exists?(completion.id)).to be(false)
    end

    it "leaves the tainted object and its audit row in place when the adapter does not implement delete" do
      completion = create_partitioned_completion(7)

      write_only_adapter = Class.new do
        def initialize(inner)
          @inner = inner
        end

        def write(**kwargs)
          @inner.write(**kwargs)
        end
      end.new(storage)
      allow(Raif.config).to receive(:archive_storage).and_return(write_only_adapter)

      mutated = false
      allow(storage).to receive(:write).and_wrap_original do |original, **kwargs|
        unless mutated
          mutated = true
          completion.update_columns(source_id: 8)
        end
        original.call(**kwargs)
      end

      expect { perform }.not_to raise_error

      # The cull still aborted, but without delete(key:) the object cannot
      # be removed, so the Raif::Archive row deliberately stays too (row
      # exists = object uploaded).
      expect(Raif::ModelCompletion.exists?(completion.id)).to be(true)
      expect(completion.raif_inference_cost_event.reload.raif_archive_id).to be_nil
      archive = Raif::Archive.sole
      expect(File.exist?(File.join(storage_root, archive.key))).to be(true)
    end

    it "keeps the audit row when deleting the tainted object fails, preserving row exists = object uploaded" do
      completion = create_partitioned_completion(7)

      mutated = false
      allow(storage).to receive(:write).and_wrap_original do |original, **kwargs|
        unless mutated
          mutated = true
          completion.update_columns(source_id: 8)
        end
        original.call(**kwargs)
      end
      allow(storage).to receive(:delete).and_raise(Raif::Errors::ArchiveStorageError, "delete exploded")

      expect { perform }.not_to raise_error

      expect(Raif::ModelCompletion.exists?(completion.id)).to be(true)
      expect(completion.raif_inference_cost_event.reload.raif_archive_id).to be_nil
      archive = Raif::Archive.sole
      expect(File.exist?(File.join(storage_root, archive.key))).to be(true)
    end

    it "logs and retains rows whose SQL partition match diverges from their normalized value" do
      completion = create_partitioned_completion(7)

      # Only possible in production under loose SQL equality (e.g. a
      # case-insensitive collation matching a mixed-case variant); simulated
      # here by forcing the normalized re-check to disagree.
      allow_any_instance_of(described_class).to receive(:partition_matches?).and_return(false)
      allow(Rails.logger).to receive(:warn).and_call_original

      perform

      expect(Raif::ModelCompletion.exists?(completion.id)).to be(true)
      expect(Raif::Archive.count).to eq(0)
      expect(Rails.logger).to have_received(:warn).with(/normalized/)
    end

    it "validates the partition column against the resource lazily, at job time" do
      allow(Raif.config).to receive(:archive_partition_column).and_return(:column_that_does_not_exist)
      create_terminal_completion

      expect { perform }.to raise_error(Raif::Errors::InvalidConfigError, /column_that_does_not_exist/)
      expect(Raif::Archive.count).to eq(0)
      expect(Raif::ModelCompletion.count).to eq(1)
    end
  end

  describe "advisory lock" do
    let!(:old_completion) { create_terminal_completion }

    it "returns immediately when another run holds the lock" do
      connection = Raif::ModelCompletion.connection
      allow(connection).to receive(:get_advisory_lock).and_return(false)
      allow(Raif::ModelCompletion).to receive(:connection).and_return(connection)

      expect { perform }.not_to change { [Raif::Archive.count, Raif::ModelCompletion.count] }
    end

    it "releases the lock after a successful run" do
      connection = Raif::ModelCompletion.connection
      allow(connection).to receive(:get_advisory_lock).and_call_original
      allow(connection).to receive(:release_advisory_lock).and_call_original
      allow(Raif::ModelCompletion).to receive(:connection).and_return(connection)

      perform

      expect(connection).to have_received(:release_advisory_lock)
    end

    it "releases the lock even when a batch raises" do
      allow(storage).to receive(:write).and_raise(IOError, "upload exploded")

      connection = Raif::ModelCompletion.connection
      allow(connection).to receive(:release_advisory_lock).and_call_original
      allow(Raif::ModelCompletion).to receive(:connection).and_return(connection)

      expect { perform }.to raise_error(IOError)
      expect(connection).to have_received(:release_advisory_lock)
    end
  end

  describe ".dry_run" do
    it "reports eligible rows (split by terminal state) and per-guard exclusions without writing anything" do
      eligible = create_terminal_completion

      zombie = FB.create(:raif_model_completion, llm_model_key: "raif_test_llm", model_api_name: "raif-test-llm")
      zombie.update_columns(created_at: 8.months.ago, updated_at: 8.months.ago)

      non_quiescent = create_terminal_completion
      non_quiescent.update_columns(updated_at: 1.hour.ago)

      batch = FB.create(:raif_model_completion_batch_anthropic, status: "in_progress")
      create_terminal_completion(raif_model_completion_batch: batch)

      missing_event = create_terminal_completion
      missing_event.raif_inference_cost_event.destroy!

      stale_event = create_terminal_completion
      stale_event.raif_inference_cost_event.update_columns(updated_at: stale_event.updated_at - 1.day)

      creator = FB.create(:raif_test_user)
      conversation = FB.create(:raif_test_conversation, creator: creator)
      entry = FB.create(:raif_conversation_entry, raif_conversation: conversation, creator: creator)
      create_terminal_completion(source: entry, citations: [{ "url" => "https://example.com" }])

      result = nil
      expect do
        result = described_class.dry_run
      end.not_to change { [Raif::Archive.count, Raif::ModelCompletion.count] }

      expect(result[:cutoff]).to be_within(1.minute).of(retention_period.ago)
      expect(result[:eligible]).to eq(2)
      expect(result[:eligible_terminal]).to eq(1)
      expect(result[:eligible_nonterminal]).to eq(1)
      expect(result[:excluded_by_quiescence]).to eq(1)
      expect(result[:excluded_by_active_batch]).to eq(1)
      expect(result[:excluded_missing_cost_event]).to eq(1)
      expect(result[:excluded_stale_cost_event]).to eq(1)
      expect(result[:excluded_uncopied_citations]).to eq(1)
      expect(Raif::ModelCompletion.exists?(eligible.id)).to be(true)

      # Partitioning unset: the report shape is unchanged.
      expect(result).not_to have_key(:partitions)
      expect(result).not_to have_key(:excluded_by_missing_partition)
    end

    it "requires a cutoff when no retention period is configured" do
      allow(Raif.config).to receive(:model_completion_retention_period).and_return(nil)

      expect { described_class.dry_run }.to raise_error(ArgumentError, /cutoff/)
      expect { described_class.dry_run(cutoff: 6.months.ago) }.not_to raise_error
    end

    context "with partitioning configured" do
      before do
        allow(Raif.config).to receive_messages(archive_partition_column: :source_id, archive_partition_fallback: nil)
      end

      def create_partitioned_completion(partition_value, **attrs)
        completion = create_terminal_completion(**attrs)
        completion.update_columns(source_id: partition_value)
        completion
      end

      it "reports per-partition eligible counts and fail-closed missing-partition exclusions" do
        2.times { create_partitioned_completion(7) }

        zombie = FB.create(:raif_model_completion, llm_model_key: "raif_test_llm", model_api_name: "raif-test-llm")
        zombie.update_columns(created_at: 8.months.ago, updated_at: 8.months.ago, source_id: 9)

        create_partitioned_completion(nil)

        result = described_class.dry_run

        expect(result[:partitions]).to eq(
          "7" => { eligible_terminal: 2, eligible_nonterminal: 0 },
          "9" => { eligible_terminal: 0, eligible_nonterminal: 1 }
        )
        expect(result[:excluded_by_missing_partition]).to eq(1)

        # The missing-partition record is retained, so the headline eligible
        # counts exclude it.
        expect(result[:eligible]).to eq(3)
        expect(result[:eligible_terminal]).to eq(2)
        expect(result[:eligible_nonterminal]).to eq(1)
      end

      it "counts NULL-partition records as an eligible ungrouped partition when the fallback is UNGROUPED" do
        allow(Raif.config).to receive(:archive_partition_fallback).and_return(Raif::Archive::UNGROUPED)

        create_partitioned_completion(nil)
        create_partitioned_completion(7)

        result = described_class.dry_run

        expect(result[:partitions]).to eq(
          "7" => { eligible_terminal: 1, eligible_nonterminal: 0 },
          nil => { eligible_terminal: 1, eligible_nonterminal: 0 }
        )
        expect(result[:excluded_by_missing_partition]).to eq(0)
        expect(result[:eligible]).to eq(2)
      end

      it "validates the partition column lazily, at dry_run time" do
        allow(Raif.config).to receive(:archive_partition_column).and_return(:column_that_does_not_exist)

        expect { described_class.dry_run }.to raise_error(Raif::Errors::InvalidConfigError, /column_that_does_not_exist/)
      end
    end
  end
end
