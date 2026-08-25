# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::ArchiveTasksJob, type: :job do
  let(:storage_root) { Dir.mktmpdir }
  let(:storage) { Raif::ArchiveStorage::FileSystem.new(root: storage_root) }
  let(:retention_period) { 12.months }

  before do
    allow(Raif.config).to receive_messages(
      archive_enabled: true,
      archive_storage: storage,
      task_retention_period: retention_period
    )
  end

  after { FileUtils.remove_entry(storage_root) }

  def create_task(created_at: 14.months.ago, **attrs)
    task = FB.create(:raif_test_task, :completed, **attrs)
    task.update_columns(created_at: created_at, updated_at: created_at)
    task
  end

  def create_completion(**attrs)
    FB.create(:raif_model_completion, llm_model_key: "raif_test_llm", model_api_name: "raif-test-llm", **attrs)
  end

  def perform(**kwargs)
    described_class.new.perform(**kwargs)
  end

  def read_archived_lines(archive)
    Zlib::GzipReader.open(File.join(storage_root, archive.key)) { |gz| gz.read.split("\n") }
  end

  def task_archives
    Raif::Archive.where(resource_type: "Raif::Task")
  end

  def invocation_archives
    Raif::Archive.where(resource_type: "Raif::ModelToolInvocation")
  end

  describe "disabled by default" do
    let!(:old_task) { create_task }

    it "no-ops when archive_enabled is false" do
      allow(Raif.config).to receive(:archive_enabled).and_return(false)

      expect { perform }.not_to change { [Raif::Archive.count, Raif::Task.count] }
    end

    it "no-ops when no storage adapter is configured" do
      allow(Raif.config).to receive(:archive_storage).and_return(nil)

      expect { perform }.not_to change { [Raif::Archive.count, Raif::Task.count] }
    end

    it "no-ops when the retention period is nil" do
      allow(Raif.config).to receive(:task_retention_period).and_return(nil)

      expect { perform }.not_to change { [Raif::Archive.count, Raif::Task.count] }
    end

    it "refuses to run with a retention period under the 1 month floor, even if boot validation was skipped" do
      allow(Raif.config).to receive(:task_retention_period).and_return(3.days)

      expect { perform }.to raise_error(Raif::Errors::InvalidConfigError, /task_retention_period must be at least 1 month/)
      expect(Raif::Task.exists?(old_task.id)).to be(true)
      expect(Raif::Archive.count).to eq(0)
    end
  end

  describe "happy path" do
    let!(:old_tasks) { 3.times.map { create_task } }
    let!(:recent_task) { create_task(created_at: 1.month.ago) }
    let!(:active_task) do
      task = create_task
      task.update_columns(updated_at: 1.hour.ago)
      task
    end

    it "archives and deletes old tasks, leaving recent and non-quiescent rows untouched" do
      perform

      expect(Raif::Task.where(id: old_tasks.map(&:id))).to be_empty
      expect(Raif::Task.exists?(recent_task.id)).to be(true)
      expect(Raif::Task.exists?(active_task.id)).to be(true)

      archive = task_archives.sole
      expect(archive.record_count).to eq(3)
      expect(archive.partition_value).to be_nil
      expect(archive.first_record_id).to eq(old_tasks.map(&:id).min)
      expect(archive.last_record_id).to eq(old_tasks.map(&:id).max)
      expect(archive.key).to start_with("raif-archives/tasks/")
      expect(archive.checksum_sha256).to eq(Digest::SHA256.file(archive.location).hexdigest)

      lines = read_archived_lines(archive)
      manifest = JSON.parse(lines.first)
      expect(manifest["resource_type"]).to eq("Raif::Task")
      expect(manifest["table"]).to eq("raif_tasks")
      expect(lines.drop(1).map { |line| JSON.parse(line)["id"] }).to match_array(old_tasks.map(&:id))
      # Raw attributes, not a projection: the archive has to round-trip.
      expect(lines.drop(1).map { |line| JSON.parse(line)["prompt"] }).to match_array(old_tasks.map(&:prompt))
    end

    it "archives a task whose STI class the host has since deleted, keeping its type in the object" do
      orphan = create_task
      orphan.update_columns(type: "Raif::Tasks::LongSinceDeleted")

      expect { described_class.new.perform }.not_to raise_error

      expect(Raif::Task.exists?(orphan.id)).to be(false)
      line = read_archived_lines(task_archives.sole).drop(1).map { |l| JSON.parse(l) }.find { |r| r["id"] == orphan.id }
      expect(line["type"]).to eq("Raif::Tasks::LongSinceDeleted")
    end

    it "archives nonterminal tasks through the same path" do
      pending_task = create_task
      pending_task.update_columns(started_at: nil, completed_at: nil, failed_at: nil, updated_at: 14.months.ago)

      perform

      expect(Raif::Task.exists?(pending_task.id)).to be(false)
      expect(task_archives.sum(:record_count)).to eq(4)
    end
  end

  describe "the completion gate" do
    let!(:task) { create_task }

    it "never culls a task whose model completion row is still present" do
      create_completion(source: task)

      perform

      expect(Raif::Task.exists?(task.id)).to be(true)
      expect(Raif::Archive.count).to eq(0)
    end

    it "culls the task once the completion has been archived away" do
      completion = create_completion(source: task)
      completion.delete

      perform

      expect(Raif::Task.exists?(task.id)).to be(false)
    end

    it "is not confused by a completion whose source is another record type" do
      create_completion(source: FB.create(:raif_test_user))

      perform

      expect(Raif::Task.exists?(task.id)).to be(false)
    end
  end

  describe "the prompt studio gate" do
    let!(:task) { create_task }

    it "retains a task a batch run item names as its source" do
      FB.create(:raif_prompt_studio_batch_run_item, source_task: task)

      perform

      expect(Raif::Task.exists?(task.id)).to be(true)
    end

    it "retains a task a batch run item names as its result" do
      FB.create(:raif_prompt_studio_batch_run_item, result_task: task)

      perform

      expect(Raif::Task.exists?(task.id)).to be(true)
    end

    it "retains a task a batch run item names as its judge" do
      FB.create(:raif_prompt_studio_batch_run_item, judge_task: task)

      perform

      expect(Raif::Task.exists?(task.id)).to be(true)
    end

    it "culls unreferenced tasks even when other tasks are referenced" do
      referenced = create_task
      FB.create(:raif_prompt_studio_batch_run_item, source_task: referenced)

      perform

      expect(Raif::Task.exists?(referenced.id)).to be(true)
      expect(Raif::Task.exists?(task.id)).to be(false)
    end
  end

  describe "the inference cost event stamp" do
    let!(:task) { create_task }

    it "stamps raif_task_archive_id before deleting the task, leaving source pointing at the culled id" do
      event = FB.create(:raif_inference_cost_event, source: task)

      perform

      archive = task_archives.sole
      event.reload
      expect(event.raif_task_archive_id).to eq(archive.id)
      expect(event.source_type).to eq("Raif::Task")
      expect(event.source_id).to eq(task.id)
      expect(Raif::Task.exists?(task.id)).to be(false)
    end

    it "culls a task that never produced a cost event" do
      expect(Raif::InferenceCostEvent.where(source: task)).to be_empty

      perform

      expect(Raif::Task.exists?(task.id)).to be(false)
      expect(task_archives.sole.record_count).to eq(1)
    end

    it "leaves a nonterminal task's events unstamped, since only terminal ids are stamped" do
      task.update_columns(completed_at: nil, failed_at: nil, updated_at: 14.months.ago)
      event = FB.create(:raif_inference_cost_event, source: task)

      perform

      expect(Raif::Task.exists?(task.id)).to be(false)
      expect(event.reload.raif_task_archive_id).to be_nil
    end
  end

  describe "model tool invocations" do
    let!(:task) { create_task }

    it "archives them into their own object and deletes them with the task" do
      invocation = FB.create(:raif_model_tool_invocation, :with_result, source: task)
      other = FB.create(:raif_model_tool_invocation, :with_result, source: create_task(created_at: 1.month.ago))

      perform

      expect(Raif::ModelToolInvocation.exists?(invocation.id)).to be(false)
      expect(Raif::ModelToolInvocation.exists?(other.id)).to be(true)

      archive = invocation_archives.sole
      expect(archive.record_count).to eq(1)
      expect(archive.first_record_id).to eq(invocation.id)
      expect(archive.key).to start_with("raif-archives/model-tool-invocations/")

      lines = read_archived_lines(archive)
      expect(JSON.parse(lines.first)["resource_type"]).to eq("Raif::ModelToolInvocation")
      expect(JSON.parse(lines.first)["table"]).to eq("raif_model_tool_invocations")
      expect(JSON.parse(lines.second)["id"]).to eq(invocation.id)
    end

    it "writes no invocation object when the batch has none" do
      perform

      expect(invocation_archives).to be_empty
      expect(task_archives.count).to eq(1)
    end

    it "keeps the invocations of a task that fell out of the eligibility recheck" do
      invocation = FB.create(:raif_model_tool_invocation, :with_result, source: task)
      # Serialize sees the task, then it becomes non-quiescent before the cull
      # transaction re-checks eligibility.
      allow_any_instance_of(described_class).to receive(:archive_dependents!).and_wrap_original do |original, *args|
        result = original.call(*args)
        task.update_columns(updated_at: Time.current)
        result
      end

      perform

      expect(Raif::Task.exists?(task.id)).to be(true)
      expect(Raif::ModelToolInvocation.exists?(invocation.id)).to be(true)
    end
  end

  describe "partitioning" do
    before do
      allow(Raif.config).to receive_messages(archive_partition_column: :source_id, archive_partition_fallback: nil)
    end

    it "writes one object per partition and files the invocations under the same partition" do
      owner_one = FB.create(:raif_test_user)
      owner_two = FB.create(:raif_test_user)
      task_one = create_task(source: owner_one)
      task_two = create_task(source: owner_two)
      invocation = FB.create(:raif_model_tool_invocation, :with_result, source: task_one)

      perform

      expect(task_archives.pluck(:partition_value)).to match_array([owner_one.id.to_s, owner_two.id.to_s])
      expect(invocation_archives.sole.partition_value).to eq(owner_one.id.to_s)
      expect(invocation_archives.sole.key).to include("model-tool-invocations")
      expect(Raif::Task.where(id: [task_one.id, task_two.id])).to be_empty
      expect(Raif::ModelToolInvocation.exists?(invocation.id)).to be(false)

      manifest = JSON.parse(read_archived_lines(invocation_archives.sole).first)
      # Named for the column it was read from, which lives on the parent task.
      expect(manifest["partition_column"]).to eq("raif_tasks.source_id")
      expect(manifest["partition_value"]).to eq(owner_one.id.to_s)
    end

    it "never archives a task whose partition value is NULL" do
      unowned = create_task(source: nil)

      perform

      expect(Raif::Task.exists?(unowned.id)).to be(true)
      expect(Raif::Archive.count).to eq(0)
    end

    it "purge_partition! nullifies the task stamp along with the completion stamp" do
      owner = FB.create(:raif_test_user)
      task = create_task(source: owner)
      event = FB.create(:raif_inference_cost_event, source: task)

      perform
      expect(event.reload.raif_task_archive_id).to be_present

      Raif::Archive.purge_partition!(partition_value: owner.id)

      expect(event.reload.raif_task_archive_id).to be_nil
      expect(Raif::Archive.count).to eq(0)
    end
  end

  describe ".dry_run" do
    it "reports eligible rows and per-guard exclusions without writing anything" do
      3.times { create_task }
      create_task(created_at: 1.month.ago)
      non_quiescent = create_task
      non_quiescent.update_columns(updated_at: 1.hour.ago)
      with_completion = create_task
      create_completion(source: with_completion)
      referenced = create_task
      FB.create(:raif_prompt_studio_batch_run_item, source_task: referenced)

      result = described_class.dry_run

      expect(result[:eligible]).to eq(3)
      expect(result[:eligible_terminal]).to eq(3)
      expect(result[:eligible_nonterminal]).to eq(0)
      expect(result[:excluded_by_quiescence]).to eq(1)
      expect(result[:excluded_by_live_model_completion]).to eq(1)
      expect(result[:excluded_by_prompt_studio]).to eq(1)
      expect(Raif::Archive.count).to eq(0)
      expect(Raif::Task.count).to eq(7)
    end

    it "requires a cutoff when no retention period is configured" do
      allow(Raif.config).to receive(:task_retention_period).and_return(nil)

      expect { described_class.dry_run }.to raise_error(ArgumentError, /task_retention_period/)
      expect { described_class.dry_run(cutoff: 12.months.ago) }.not_to raise_error
    end
  end
end
