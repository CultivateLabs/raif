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

    it "retains and reports nonterminal stragglers without archiving them" do
      straggler = FB.create(:raif_model_completion, llm_model_key: "raif_test_llm", model_api_name: "raif-test-llm")
      straggler.update_columns(created_at: 8.months.ago, updated_at: 8.months.ago)

      allow(Raif.logger).to receive(:warn)

      perform

      expect(Raif::ModelCompletion.exists?(straggler.id)).to be(true)
      expect(Raif::Archive.count).to eq(0)
      expect(Raif.logger).to have_received(:warn).with(/1 nonterminal model completion/)
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

      perform(max_batches: 4)

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

    it "respects max_batches, processing oldest completions first" do
      stub_const("Raif::ArchiveModelCompletionsJob::BATCH_RECORD_LIMIT", 1)

      oldest = create_terminal_completion(created_at: 10.months.ago)
      middle = create_terminal_completion(created_at: 9.months.ago)
      newest = create_terminal_completion(created_at: 8.months.ago)

      perform(max_batches: 2)

      expect(Raif::Archive.count).to eq(2)
      expect(Raif::ModelCompletion.exists?(oldest.id)).to be(false)
      expect(Raif::ModelCompletion.exists?(middle.id)).to be(false)
      expect(Raif::ModelCompletion.exists?(newest.id)).to be(true)
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
    it "reports eligible rows, nonterminal stragglers, and per-guard exclusions without writing anything" do
      eligible = create_terminal_completion

      straggler = FB.create(:raif_model_completion, llm_model_key: "raif_test_llm", model_api_name: "raif-test-llm")
      straggler.update_columns(created_at: 8.months.ago, updated_at: 8.months.ago)

      non_quiescent = create_terminal_completion
      non_quiescent.update_columns(updated_at: 1.hour.ago)

      batch = FB.create(:raif_model_completion_batch_anthropic, status: "in_progress")
      create_terminal_completion(raif_model_completion_batch: batch)

      missing_event = create_terminal_completion
      missing_event.raif_inference_cost_event.destroy!

      creator = FB.create(:raif_test_user)
      conversation = FB.create(:raif_test_conversation, creator: creator)
      entry = FB.create(:raif_conversation_entry, raif_conversation: conversation, creator: creator)
      create_terminal_completion(source: entry, citations: [{ "url" => "https://example.com" }])

      result = nil
      expect do
        result = described_class.dry_run
      end.not_to change { [Raif::Archive.count, Raif::ModelCompletion.count] }

      expect(result[:cutoff]).to be_within(1.minute).of(retention_period.ago)
      expect(result[:eligible]).to eq(1)
      expect(result[:nonterminal_stragglers]).to eq(1)
      expect(result[:excluded_by_quiescence]).to eq(1)
      expect(result[:excluded_by_active_batch]).to eq(1)
      expect(result[:excluded_missing_cost_event]).to eq(1)
      expect(result[:excluded_uncopied_citations]).to eq(1)
      expect(Raif::ModelCompletion.exists?(eligible.id)).to be(true)
    end

    it "requires a cutoff when no retention period is configured" do
      allow(Raif.config).to receive(:model_completion_retention_period).and_return(nil)

      expect { described_class.dry_run }.to raise_error(ArgumentError, /cutoff/)
      expect { described_class.dry_run(cutoff: 6.months.ago) }.not_to raise_error
    end
  end
end
