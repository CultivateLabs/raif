# frozen_string_literal: true

require "rails_helper"

class Raif::TestOutputLimitsTask < Raif::Task
  llm_response_format :json
  llm_max_completion_tokens 8_000
  llm_stop_sequences ["END_OF_ANSWER", "<<halt>>"]
  llm_fail_on_truncation true

  def build_prompt
    "Return a JSON object"
  end
end

RSpec.describe Raif::Concerns::LlmOutputLimits do
  let(:creator) { FB.create(:raif_test_user) }

  describe "the class settings" do
    it "is unset by default" do
      expect(Raif::TestTask.max_completion_tokens).to be_nil
      expect(Raif::TestTask.stop_sequences).to be_nil
      expect(Raif::TestTask.fail_on_truncation).to be(false)
    end

    it "carries a per-class declaration" do
      expect(Raif::TestOutputLimitsTask.max_completion_tokens).to eq(8_000)
      expect(Raif::TestOutputLimitsTask.stop_sequences).to eq(["END_OF_ANSWER", "<<halt>>"])
      expect(Raif::TestOutputLimitsTask.fail_on_truncation).to be(true)
    end

    it "rejects invalid declarations" do
      task_class = Class.new(Raif::Task)

      expect { task_class.llm_max_completion_tokens(0) }.to raise_error(ArgumentError)
      expect { task_class.llm_max_completion_tokens("8000") }.to raise_error(ArgumentError)
      expect { task_class.llm_stop_sequences([]) }.to raise_error(ArgumentError)
      expect { task_class.llm_stop_sequences(["a", " "]) }.to raise_error(ArgumentError)
      expect { task_class.llm_stop_sequences(%w[a b c d e f]) }.to raise_error(ArgumentError)
      expect { task_class.llm_stop_sequences("a") }.to raise_error(ArgumentError)
      expect { task_class.llm_fail_on_truncation("yes") }.to raise_error(ArgumentError)
    end
  end

  describe "the provider request" do
    def request_parameters(llm_model_key, model_completion)
      Raif.llm(llm_model_key.to_sym).send(:build_request_parameters, model_completion)
    end

    context "on the sync path" do
      def run_task(task_class, llm_model_key)
        stub_raif_task(task_class) { { "answer" => 1 } }
        task_class.run(creator: creator, llm_model_key: llm_model_key)
      end

      it "sends the cap and the stop sequences to Anthropic" do
        task = run_task(Raif::TestOutputLimitsTask, "anthropic_claude_4_5_haiku")
        parameters = request_parameters("anthropic_claude_4_5_haiku", task.raif_model_completion)

        expect(parameters[:max_tokens]).to eq(8_000)
        expect(parameters[:stop_sequences]).to eq(["END_OF_ANSWER", "<<halt>>"])
      end

      it "sends the cap and the stop sequences to Google" do
        task = run_task(Raif::TestOutputLimitsTask, "google_gemini_2_5_flash")
        parameters = request_parameters("google_gemini_2_5_flash", task.raif_model_completion)

        expect(parameters[:generationConfig][:maxOutputTokens]).to eq(8_000)
        expect(parameters[:generationConfig][:stopSequences]).to eq(["END_OF_ANSWER", "<<halt>>"])
      end

      it "sends the cap but no stop sequences to OpenAI Responses" do
        task = run_task(Raif::TestOutputLimitsTask, "open_ai_responses_gpt_4o")
        parameters = request_parameters("open_ai_responses_gpt_4o", task.raif_model_completion)

        expect(parameters[:max_output_tokens]).to eq(8_000)
        expect(parameters.to_json).not_to include("END_OF_ANSWER")
      end

      it "sends the cap but no stop sequences to xAI" do
        task = run_task(Raif::TestOutputLimitsTask, "x_ai_grok_4_3")
        parameters = request_parameters("x_ai_grok_4_3", task.raif_model_completion)

        expect(parameters[:max_tokens]).to eq(8_000)
        expect(parameters.to_json).not_to include("END_OF_ANSWER")
      end

      it "keeps the model defaults for a task that declares nothing" do
        task = run_task(Raif::TestTask, "anthropic_claude_4_5_haiku")
        parameters = request_parameters("anthropic_claude_4_5_haiku", task.raif_model_completion)

        expect(parameters[:max_tokens]).to eq(Raif.llm(:anthropic_claude_4_5_haiku).default_max_completion_tokens)
        expect(parameters).not_to have_key(:stop_sequences)
        expect(task.raif_model_completion.request_settings).not_to have_key("stop_sequences")
      end
    end

    # A batch request is built at submit time from the reloaded completion, so
    # the settings have to survive on the row.
    context "on the batch path" do
      def build_reloaded_completion(llm_model_key, batch_class)
        batch = batch_class.create!(
          llm_model_key: llm_model_key,
          model_api_name: Raif.llm(llm_model_key.to_sym).api_name,
          completion_handler_class_name: "Raif::TaskBatchCompletionHandler"
        )
        task = Raif::TestOutputLimitsTask.build_for_batch(batch: batch, creator: creator, llm_model_key: llm_model_key)
        Raif::ModelCompletion.find(task.raif_model_completion.id)
      end

      it "sends the cap and the stop sequences to Anthropic" do
        completion = build_reloaded_completion("anthropic_claude_4_5_haiku", Raif::ModelCompletionBatches::Anthropic)
        parameters = request_parameters("anthropic_claude_4_5_haiku", completion)

        expect(parameters[:max_tokens]).to eq(8_000)
        expect(parameters[:stop_sequences]).to eq(["END_OF_ANSWER", "<<halt>>"])
      end

      it "sends the cap and the stop sequences to Google" do
        completion = build_reloaded_completion("google_gemini_2_5_flash", Raif::ModelCompletionBatches::Google)
        parameters = request_parameters("google_gemini_2_5_flash", completion)

        expect(parameters[:generationConfig][:maxOutputTokens]).to eq(8_000)
        expect(parameters[:generationConfig][:stopSequences]).to eq(["END_OF_ANSWER", "<<halt>>"])
      end

      it "sends the cap but no stop sequences to OpenAI" do
        completion = build_reloaded_completion("open_ai_responses_gpt_4o", Raif::ModelCompletionBatches::OpenAi)
        parameters = request_parameters("open_ai_responses_gpt_4o", completion)

        expect(parameters[:max_output_tokens]).to eq(8_000)
        expect(parameters.to_json).not_to include("END_OF_ANSWER")
      end
    end
  end

  describe "truncation" do
    def run_with_finish_reason(task_class, finish_reason)
      stub_raif_task(task_class) do |_messages, model_completion|
        model_completion.response_finish_reason = finish_reason
        "{\"answer\": "
      end

      task_class.run(creator: creator, llm_model_key: "anthropic_claude_4_5_haiku")
    end

    %w[max_tokens MAX_TOKENS].each do |finish_reason|
      it "fails an opted-in task whose completion ends with #{finish_reason}" do
        task = run_with_finish_reason(Raif::TestOutputLimitsTask, finish_reason)

        expect(task).to be_failed
        expect(task.raif_model_completion).to be_failed
        expect(task.raif_model_completion.reload.completed_at).to be_nil
        expect(task.raif_model_completion.failure_error).to eq("Raif::Errors::TruncatedResponseError")
        expect(task.raif_model_completion.failure_reason).to eq("Response truncated (finish reason: #{finish_reason})")
      end
    end

    it "completes an opted-in task whose completion ends normally" do
      stub_raif_task(Raif::TestOutputLimitsTask) do |_messages, model_completion|
        model_completion.response_finish_reason = "end_turn"
        { "answer" => 1 }
      end

      task = Raif::TestOutputLimitsTask.run(creator: creator, llm_model_key: "anthropic_claude_4_5_haiku")

      expect(task).to be_completed
      expect(task.raif_model_completion.failure_error).to be_nil
    end

    it "completes an opted-in task whose completion ends on a stop sequence" do
      task = run_with_finish_reason(Raif::TestOutputLimitsTask, "stop_sequence")

      expect(task).to be_completed
      expect(task.raif_model_completion).not_to be_failed
    end

    it "completes a task that did not opt in, as before" do
      task = run_with_finish_reason(Raif::TestTask, "max_tokens")

      expect(task).to be_completed
      expect(task.raif_model_completion).not_to be_failed
    end
  end

  describe "the persisted stop sequences" do
    let(:model_completion) do
      Raif::ModelCompletion.new(llm_model_key: "anthropic_claude_4_5_haiku", model_api_name: "claude-haiku-4-5")
    end

    it "accepts 1 to 5 non-blank strings" do
      model_completion.stop_sequences = %w[a b c d e]

      expect(model_completion).to be_valid
    end

    it "rejects any other value" do
      [%w[a b c d e f], [""], [1], "a"].each do |value|
        model_completion.request_settings = { "stop_sequences" => value }

        expect(model_completion).not_to be_valid
        expect(model_completion.errors[:request_settings].join).to include("stop_sequences must be an array")
      end
    end
  end
end
