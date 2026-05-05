# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::TaskBatchCompletionHandler do
  let(:creator) { FB.build(:raif_test_user) }
  let(:batch) { FB.create(:raif_model_completion_batch_anthropic) }

  describe ".handle_batch_completion" do
    it "runs the registered on_batch_completion block with `batch` and `tasks` accessible" do
      task_a = Raif::TestTask.build_for_batch(
        batch: batch, batch_custom_id: "a", creator: creator, llm_model_key: "anthropic_claude_3_5_haiku"
      )
      task_b = Raif::TestTask.build_for_batch(
        batch: batch, batch_custom_id: "b", creator: creator, llm_model_key: "anthropic_claude_3_5_haiku"
      )

      task_a.raif_model_completion.update!(raw_response: "a")
      task_a.raif_model_completion.completed!
      task_b.raif_model_completion.update!(raw_response: "b")
      task_b.raif_model_completion.completed!

      handler = Class.new(Raif::TaskBatchCompletionHandler) do
        cattr_accessor :captured_batch, :captured_tasks
        on_batch_completion do
          self.class.captured_batch = batch
          self.class.captured_tasks = tasks
        end
      end

      handler.handle_batch_completion(batch)

      expect(handler.captured_batch).to eq(batch)
      expect(handler.captured_tasks.map(&:id)).to contain_exactly(task_a.id, task_b.id)
      expect(handler.captured_tasks).to all(be_completed)
    end

    it "is a no-op when no on_batch_completion block has been registered (hydration still runs)" do
      task = Raif::TestTask.build_for_batch(
        batch: batch, batch_custom_id: "x", creator: creator, llm_model_key: "anthropic_claude_3_5_haiku"
      )
      task.raif_model_completion.update!(raw_response: "x")
      task.raif_model_completion.completed!

      expect { described_class.handle_batch_completion(batch) }.not_to raise_error
      expect(task.reload).to be_completed
    end
  end

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

  describe ".hydrate_tasks idempotency" do
    it "skips tasks already in a terminal state" do
      task = Raif::TestTask.build_for_batch(
        batch: batch, batch_custom_id: "done", creator: creator, llm_model_key: "anthropic_claude_3_5_haiku"
      )
      mc = task.raif_model_completion
      mc.update!(raw_response: "answer")
      mc.completed!

      # Simulate a previous handler dispatch having already completed the task.
      task.update!(raw_response: "previously-set", completed_at: 1.hour.ago)
      original_completed_at = task.completed_at

      expect_any_instance_of(Raif::TestTask).not_to receive(:process_completion!)

      described_class.hydrate_tasks(batch)

      task.reload
      expect(task.raw_response).to eq("previously-set")
      expect(task.completed_at).to be_within(1.second).of(original_completed_at)
    end
  end

  describe "subclassing" do
    it "isolates each subclass's on_batch_completion block (class_attribute inheritance)" do
      parent = Class.new(Raif::TaskBatchCompletionHandler) do
        cattr_accessor :calls
        self.calls = []
        on_batch_completion { self.class.calls << :parent }
      end

      child = Class.new(parent) do
        on_batch_completion { self.class.calls << :child }
      end

      task = Raif::TestTask.build_for_batch(
        batch: batch, batch_custom_id: "iso", creator: creator, llm_model_key: "anthropic_claude_3_5_haiku"
      )
      task.raif_model_completion.update!(raw_response: "ok")
      task.raif_model_completion.completed!

      child.handle_batch_completion(batch)
      parent.handle_batch_completion(batch)

      expect(parent.calls).to eq([:child, :parent])
    end

    it "lets the block call helper methods defined on the subclass" do
      handler = Class.new(Raif::TaskBatchCompletionHandler) do
        cattr_accessor :captured_summary

        on_batch_completion do
          self.class.captured_summary = summarize
        end

        def summarize
          "#{tasks.size} task(s) for batch ##{batch.id}"
        end
      end

      Raif::TestTask.build_for_batch(
        batch: batch, batch_custom_id: "h", creator: creator, llm_model_key: "anthropic_claude_3_5_haiku"
      ).raif_model_completion.tap do |mc|
        mc.update!(raw_response: "ok")
        mc.completed!
      end

      handler.handle_batch_completion(batch)

      expect(handler.captured_summary).to eq("1 task(s) for batch ##{batch.id}")
    end

    it "lets the block use `next` for early exit" do
      handler = Class.new(Raif::TaskBatchCompletionHandler) do
        cattr_accessor :reached_tail
        self.reached_tail = false

        on_batch_completion do
          next if tasks.empty?

          self.class.reached_tail = true
        end
      end

      # Empty batch: tasks comes back empty, block should `next` out before flipping reached_tail.
      handler.handle_batch_completion(batch)
      expect(handler.reached_tail).to be(false)
    end
  end

  describe "whole-batch failure routing" do
    it "calls process_completion! for force-failed completions so tasks transition to failed" do
      task = Raif::TestTask.build_for_batch(
        batch: batch, batch_custom_id: "fail", creator: creator, llm_model_key: "anthropic_claude_3_5_haiku"
      )

      # Simulate Raif::ModelCompletionBatch#force_fail! having marked the child
      # completion as failed (no raw_response, just failure_error/reason).
      mc = task.raif_model_completion
      mc.failure_error = "Raif::ModelCompletionBatch ##{batch.id} canceled"
      mc.failure_reason = "synthetic batch cancel"
      mc.failed!

      tasks = described_class.hydrate_tasks(batch)

      expect(tasks.map(&:id)).to eq([task.id])
      expect(task.reload).to be_failed
    end
  end
end
