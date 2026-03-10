# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::PromptStudioTaskRunJob, type: :job do
  include ActiveJob::TestHelper

  let(:creator) { FB.create(:raif_test_user) }
  let(:task) { FB.create(:raif_test_task, creator: creator, started_at: Time.current, prompt_studio_run: true) }

  describe "#perform" do
    it "runs the task and broadcasts the result" do
      stub_raif_task(Raif::TestTask) { "Stubbed response" }

      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
        task,
        target: ActionView::RecordIdentifier.dom_id(task, :result),
        html: a_string_including("Stubbed response")
      )

      described_class.new.perform(task: task)

      task.reload
      expect(task.completed_at).to be_present
      expect(task.raw_response).to eq("Stubbed response")
    end

    context "when the task has a source task" do
      let(:source_task) { FB.create(:raif_test_task, :completed, creator: creator) }
      let(:task) { FB.create(:raif_test_task, creator: creator, source: source_task, started_at: Time.current, prompt_studio_run: true) }

      it "includes the original and new responses in the broadcast" do
        stub_raif_task(Raif::TestTask) { "Stubbed response" }

        expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
          task,
          target: ActionView::RecordIdentifier.dom_id(task, :result),
          html: a_string_including("Original Response", "New Response")
        )

        described_class.new.perform(task: task)
      end
    end

    context "when the task fails" do
      before do
        allow(task).to receive(:run).and_raise(StandardError.new("LLM error"))
      end

      it "marks the task as failed and broadcasts the result" do
        expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
          task,
          target: ActionView::RecordIdentifier.dom_id(task, :result),
          html: a_string_including("Failed")
        )

        described_class.new.perform(task: task)

        task.reload
        expect(task.failed_at).to be_present
      end
    end
  end
end
