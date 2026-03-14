# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::PromptStudioBatchRunItemJob, type: :job do
  let(:creator) { FB.create(:raif_test_user) }
  let(:batch_run) { FB.create(:raif_prompt_studio_batch_run, total_count: 1) }
  let(:source_task) { FB.create(:raif_test_task, :completed, creator: creator) }
  let!(:item) { batch_run.items.create!(source_task: source_task) }

  it "delegates to item.execute!" do
    expect(item).to receive(:execute!)
    described_class.perform_now(item: item)
  end
end
