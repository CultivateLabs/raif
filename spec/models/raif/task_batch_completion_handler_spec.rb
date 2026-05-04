# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::TaskBatchCompletionHandler do
  let(:creator) { FB.build(:raif_test_user) }
  let(:batch) { FB.create(:raif_model_completion_batch_anthropic) }

  it "routes each child completion through its source task's #process_completion!" do
    success_task = Raif::TestTask.build_for_batch(
      batch: batch,
      batch_custom_id: "win",
      creator: creator,
      llm_model_key: "anthropic_claude_3_5_haiku"
    )

    fail_task = Raif::TestTask.build_for_batch(
      batch: batch,
      batch_custom_id: "lose",
      creator: creator,
      llm_model_key: "anthropic_claude_3_5_haiku"
    )

    # Pretend the provider's batch results pipeline ran: success_task's
    # completion is completed with raw_response, fail_task's is failed.
    success_mc = success_task.raif_model_completion
    success_mc.update!(raw_response: "completed answer")
    success_mc.completed!

    fail_mc = fail_task.raif_model_completion
    fail_mc.failure_error = "Anthropic batch entry errored"
    fail_mc.failure_reason = "boom"
    fail_mc.failed!

    described_class.handle_batch_completion(batch)

    expect(success_task.reload).to be_completed
    expect(success_task.raw_response).to eq("completed answer")

    expect(fail_task.reload).to be_failed
  end

  it "logs a warning when a child completion's source is not a Raif::Task" do
    mc = FB.create(
      :raif_model_completion,
      raif_model_completion_batch: batch,
      batch_custom_id: "no_source",
      model_api_name: "claude-3-5-haiku-latest",
      llm_model_key: "anthropic_claude_3_5_haiku",
      source: nil
    )
    mc.update!(raw_response: "ignored")
    mc.completed!

    expect(Raif.logger).to receive(:warn).with(a_string_matching(/expected a Raif::Task/))
    expect { described_class.handle_batch_completion(batch) }.not_to raise_error
  end

  it "catches per-task exceptions and continues processing the rest" do
    good_task = Raif::TestTask.build_for_batch(
      batch: batch,
      batch_custom_id: "good",
      creator: creator,
      llm_model_key: "anthropic_claude_3_5_haiku"
    )
    bad_task = Raif::TestTask.build_for_batch(
      batch: batch,
      batch_custom_id: "bad",
      creator: creator,
      llm_model_key: "anthropic_claude_3_5_haiku"
    )

    good_task.raif_model_completion.update!(raw_response: "good answer")
    good_task.raif_model_completion.completed!
    bad_task.raif_model_completion.update!(raw_response: "bad answer")
    bad_task.raif_model_completion.completed!

    bad_task_id = bad_task.id
    original = Raif::TestTask.instance_method(:process_completion!)
    allow_any_instance_of(Raif::TestTask).to receive(:process_completion!) do |task, mc|
      raise "synthetic-error" if task.id == bad_task_id

      original.bind_call(task, mc)
    end

    allow(Raif.logger).to receive(:error)

    described_class.handle_batch_completion(batch)

    expect(good_task.reload).to be_completed
    expect(bad_task.reload).not_to be_completed

    expect(Raif.logger).to have_received(:error).with(a_string_matching(/failed to process Raif::Task ##{bad_task_id}/)).once
  end
end
