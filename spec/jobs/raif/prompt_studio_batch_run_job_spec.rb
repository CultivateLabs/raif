# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::PromptStudioBatchRunJob, type: :job do
  let(:creator) { FB.create(:raif_test_user) }
  let(:batch_run) { FB.create(:raif_prompt_studio_batch_run, total_count: 2) }

  before do
    2.times do
      source_task = FB.create(:raif_test_task, :completed, creator: creator)
      batch_run.items.create!(source_task: source_task)
    end
  end

  it "sets started_at on the batch run" do
    described_class.perform_now(batch_run: batch_run)
    expect(batch_run.reload.started_at).to be_present
  end

  it "enqueues an item job for each pending item" do
    expect do
      described_class.perform_now(batch_run: batch_run)
    end.to have_enqueued_job(Raif::PromptStudioBatchRunItemJob).exactly(2).times
  end

  it "does not enqueue jobs for non-pending items" do
    batch_run.items.first.update!(status: "completed")

    expect do
      described_class.perform_now(batch_run: batch_run)
    end.to have_enqueued_job(Raif::PromptStudioBatchRunItemJob).exactly(1).times
  end
end
