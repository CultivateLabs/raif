# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Raif::Task batch preparation" do
  let(:batch) { FB.create(:raif_model_completion_batch_anthropic) }
  let(:creator) { FB.build(:raif_test_user) }

  describe ".build_for_batch" do
    it "persists the task in :pending state with prompts populated" do
      task = Raif::TestTask.build_for_batch(
        batch: batch,
        creator: creator,
        llm_model_key: "anthropic_claude_3_5_haiku"
      )

      expect(task).to be_persisted
      expect(task.status).to eq(:pending)
      expect(task.started_at).to be_nil
      expect(task.prompt).to eq("Tell me a joke")
      expect(task.system_prompt).to include("You are also good at telling jokes.")
    end

    it "creates a pending Raif::ModelCompletion attached to the batch" do
      task = Raif::TestTask.build_for_batch(
        batch: batch,
        creator: creator,
        llm_model_key: "anthropic_claude_3_5_haiku"
      )

      mc = task.raif_model_completion
      expect(mc).to be_present
      expect(mc).to be_persisted
      expect(mc).to be_pending
      expect(mc.raif_model_completion_batch).to eq(batch)
      expect(mc.source).to eq(task)
      expect(mc.llm_model_key).to eq("anthropic_claude_3_5_haiku")
      expect(mc.model_api_name).to eq("claude-3-5-haiku-latest")
      expect(mc.system_prompt).to include("You are also good at telling jokes.")
      expect(mc.messages).to eq([{ "role" => "user", "content" => [{ "type" => "text", "text" => "Tell me a joke" }] }])
    end

    it "defaults provider_request_id to raif_task_<id>" do
      task = Raif::TestTask.build_for_batch(
        batch: batch,
        creator: creator,
        llm_model_key: "anthropic_claude_3_5_haiku"
      )

      expect(task.raif_model_completion.provider_request_id).to eq("raif_task_#{task.id}")
    end

    it "honors a caller-supplied custom_request_id" do
      task = Raif::TestTask.build_for_batch(
        batch: batch,
        custom_request_id: "explicit-custom-id",
        creator: creator,
        llm_model_key: "anthropic_claude_3_5_haiku"
      )

      expect(task.raif_model_completion.provider_request_id).to eq("explicit-custom-id")
    end

    it "propagates anthropic_prompt_caching_enabled from the task class" do
      task = Raif::TestCachedTask.build_for_batch(
        batch: batch,
        creator: creator,
        llm_model_key: "anthropic_claude_3_5_haiku"
      )

      expect(task.raif_model_completion.anthropic_prompt_caching_enabled).to be(true)
    end

    it "propagates response_format and json_response_schema for JSON tasks" do
      task = Raif::TestJsonTask.build_for_batch(
        batch: batch,
        creator: creator,
        llm_model_key: "anthropic_claude_3_5_haiku"
      )

      expect(task.raif_model_completion.response_format).to eq("json")
      # The schema is reachable from the model completion via the task source.
      expect(task.raif_model_completion.json_response_schema).to be_present
    end
  end

  describe "#prepare_for_batch!" do
    it "is idempotent on prompt population" do
      task = Raif::TestTask.new(creator: creator, llm_model_key: "anthropic_claude_3_5_haiku")
      task.save!

      task.prepare_for_batch!(batch: batch)

      # Mutate the persisted prompts so we can detect any unwanted re-population
      # by build_prompt/build_system_prompt on the second call.
      sentinel_prompt = "FROZEN_PROMPT_SENTINEL"
      sentinel_system_prompt = "FROZEN_SYSTEM_PROMPT_SENTINEL"
      task.update!(prompt: sentinel_prompt, system_prompt: sentinel_system_prompt)

      task.prepare_for_batch!(batch: batch)
      expect(task.prompt).to eq(sentinel_prompt)
      expect(task.system_prompt).to eq(sentinel_system_prompt)
    end
  end
end
