# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Llm, type: :model do
  describe "#chat" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:system_prompt) { "You are a helpful assistant." }

    let(:test_llm) do
      Raif::Llms::TestLlm.new(key: :raif_test_llm, api_name: "test_api")
    end

    context "when llm_api_requests_enabled is false" do
      before do
        allow(Raif.config).to receive(:llm_api_requests_enabled).and_return(false)
      end

      it "does not create a ModelCompletion" do
        expect(Raif::ModelCompletion).to_not receive(:new)
        result = test_llm.chat(messages: messages)
        expect(result).to be_nil
      end
    end

    context "when llm_api_requests_enabled is true" do
      before do
        allow(Raif.config).to receive(:llm_api_requests_enabled).and_return(true)

        stub_raif_llm(test_llm) do |messages|
          "This is a test response for: #{messages[0]["content"][0]["text"]}"
        end
      end

      it "creates a ModelCompletion" do
        result = test_llm.chat(messages: messages, system_prompt: system_prompt)

        expect(result).to be_a(Raif::ModelCompletion)
        expect(result).to be_persisted
        expect(result.llm_model_key).to eq("raif_test_llm")
        expect(result.response_format).to eq("text")
        expect(result.raw_response).to eq("This is a test response for: Hello")
        expect(result.source).to eq(nil)
        expect(result.messages).to eq([{ "role" => "user", "content" => [{ "text" => "Hello", "type" => "text" }] }])
        expect(result.system_prompt).to eq("You are a helpful assistant.")
        expect(result.completion_tokens).to be_present
        expect(result.prompt_tokens).to be_present
        expect(result.total_tokens).to be_present
      end

      it "sets the source if provided" do
        user = FB.create(:raif_test_user)
        result = test_llm.chat(messages: messages, system_prompt: system_prompt, source: user)

        expect(result).to be_a(Raif::ModelCompletion)
        expect(result).to be_persisted
        expect(result.llm_model_key).to eq("raif_test_llm")
        expect(result.response_format).to eq("text")
        expect(result.raw_response).to eq("This is a test response for: Hello")
        expect(result.source).to eq(user)
        expect(result.messages).to eq([{ "role" => "user", "content" => [{ "text" => "Hello", "type" => "text" }] }])
        expect(result.system_prompt).to eq("You are a helpful assistant.")
        expect(result.completion_tokens).to be_present
        expect(result.prompt_tokens).to be_present
        expect(result.total_tokens).to be_present
      end

      it "persists the model completion even if the LLM API request fails" do
        allow(Raif.config).to receive(:llm_request_retriable_exceptions).and_return([])
        allow(test_llm).to receive(:perform_model_completion!).and_raise(Faraday::ConnectionFailed.new("Connection failed"))

        expect do
          test_llm.chat(messages: messages, system_prompt: system_prompt)
        end.to raise_error(Faraday::ConnectionFailed).and change(Raif::ModelCompletion, :count).by(1)

        mc = Raif::ModelCompletion.newest_first.first
        expect(mc.messages).to eq([{ "role" => "user", "content" => [{ "text" => "Hello", "type" => "text" }] }])
        expect(mc.raw_response).to eq(nil)
        expect(mc.retry_count).to eq(0)
      end

      it "records failure when Faraday::Error occurs" do
        allow(Raif.config).to receive(:llm_request_retriable_exceptions).and_return([])
        allow(test_llm).to receive(:perform_model_completion!).and_raise(Faraday::ConnectionFailed.new("Connection failed"))

        expect do
          test_llm.chat(messages: messages, system_prompt: system_prompt)
        end.to raise_error(Faraday::ConnectionFailed)

        mc = Raif::ModelCompletion.newest_first.first
        expect(mc.failed?).to be true
        expect(mc.failure_error).to eq("Faraday::ConnectionFailed")
        expect(mc.failure_reason).to eq("Connection failed")
      end

      it "records failure when StandardError occurs" do
        allow(Raif.config).to receive(:llm_request_retriable_exceptions).and_return([])
        allow(test_llm).to receive(:perform_model_completion!).and_raise(StandardError.new("Unexpected error"))

        expect do
          test_llm.chat(messages: messages, system_prompt: system_prompt)
        end.to raise_error(StandardError)

        mc = Raif::ModelCompletion.newest_first.first
        expect(mc.failed?).to be true
        expect(mc.failure_error).to eq("StandardError")
        expect(mc.failure_reason).to eq("Unexpected error")
      end

      it "does not record failure on success" do
        result = test_llm.chat(messages: messages, system_prompt: system_prompt)

        expect(result.failed?).to be false
        expect(result.failure_error).to be_nil
        expect(result.failure_reason).to be_nil
      end
    end

    context "with invalid response_format" do
      it "raises an error when response_format is not a symbol" do
        expect do
          test_llm.chat(messages: messages, response_format: "text")
        end.to raise_error(ArgumentError, /Invalid response format/)
      end

      it "raises an error when response_format is not valid" do
        expect do
          test_llm.chat(messages: messages, response_format: :invalid)
        end.to raise_error(ArgumentError, /Invalid response format/)
      end
    end
  end

  describe "retry functionality" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:retry_exception) { Faraday::ConnectionFailed.new("Connection failed") }
    let(:non_retry_exception) { StandardError.new("Standard error") }

    let(:retriable_llm_class) do
      Class.new(Raif::Llm) do
        def initialize(failures_before_success: 0, exception_to_raise: nil, **args)
          @failures_before_success = failures_before_success
          @exception_to_raise = exception_to_raise
          @attempts = 0
          super(**args)
        end

        def perform_model_completion!(model_completion)
          @attempts += 1

          if @attempts <= @failures_before_success
            raise @exception_to_raise
          end

          model_completion.raw_response = "Success after #{@attempts} attempts"
          model_completion.completion_tokens = 100
          model_completion.prompt_tokens = 100
          model_completion.total_tokens = 200
          model_completion.save!

          model_completion
        end
      end
    end

    before do
      allow(Raif.config).to receive(:llm_api_requests_enabled).and_return(true)
      allow(Raif.config).to receive(:llm_request_max_retries).and_return(2)
      allow(Raif.config).to receive(:llm_request_retriable_exceptions).and_return([Faraday::ConnectionFailed])

      # Register a test LLM in the registry for validation
      Raif.register_llm(retriable_llm_class, {
        key: :test_retry_llm,
        api_name: "test_retry_api"
      })
    end

    after do
      Raif.llm_registry.delete(:test_retry_llm)
    end

    context "when exceptions are retriable" do
      it "retries the specified number of times and succeeds" do
        llm = retriable_llm_class.new(
          failures_before_success: 2,
          exception_to_raise: retry_exception,
          key: :test_retry_llm,
          api_name: "test_retry_api"
        )
        allow(llm).to receive(:sleep) # Skip sleep delay in tests

        result = llm.chat(messages: messages)

        expect(result).to be_a(Raif::ModelCompletion)
        expect(result.raw_response).to eq("Success after 3 attempts")
        expect(result.retry_count).to eq(2)
        expect(result).to be_persisted
      end

      it "retries the specified number of times and fails if max retries exceeded" do
        llm = retriable_llm_class.new(
          failures_before_success: 3, # more than max retries (2) so that this fails before succeeding
          exception_to_raise: retry_exception,
          key: :test_retry_llm,
          api_name: "test_retry_api"
        )
        allow(llm).to receive(:sleep) # Skip sleep delay in tests

        expect(Raif::ModelCompletion.count).to eq(0)
        expect do
          llm.chat(messages: messages)
        end.to raise_error(Faraday::ConnectionFailed)

        expect(Raif::ModelCompletion.count).to eq(1)
        mc = Raif::ModelCompletion.last
        expect(mc.messages).to eq([{ "role" => "user", "content" => [{ "text" => "Hello", "type" => "text" }] }])
        expect(mc.raw_response).to eq(nil)
        expect(mc.retry_count).to eq(2)
      end

      it "records failure after retries exhausted" do
        llm = retriable_llm_class.new(
          failures_before_success: 3, # more than max retries (2) so that this fails before succeeding
          exception_to_raise: retry_exception,
          key: :test_retry_llm,
          api_name: "test_retry_api"
        )
        allow(llm).to receive(:sleep) # Skip sleep delay in tests

        expect do
          llm.chat(messages: messages)
        end.to raise_error(Faraday::ConnectionFailed)

        mc = Raif::ModelCompletion.last
        expect(mc.failed?).to be true
        expect(mc.failure_error).to eq("Faraday::ConnectionFailed")
        expect(mc.failure_reason).to eq("Connection failed")
      end
    end

    context "when exceptions are not retriable" do
      it "does not retry for non-retriable exceptions" do
        llm = retriable_llm_class.new(
          failures_before_success: 1,
          exception_to_raise: non_retry_exception,
          key: :test_retry_llm,
          api_name: "test_retry_api"
        )

        expect do
          llm.chat(messages: messages)
        end.to raise_error(StandardError)
      end
    end

    context "when Raif.config.llm_request_max_retries is 0" do
      before do
        allow(Raif.config).to receive(:llm_request_max_retries).and_return(0)
      end

      it "does not retry" do
        llm = retriable_llm_class.new(
          failures_before_success: 1,
          exception_to_raise: retry_exception,
          key: :test_retry_llm,
          api_name: "test_retry_api"
        )

        expect do
          llm.chat(messages: messages)
        end.to raise_error(Faraday::ConnectionFailed)
      end
    end
  end

  it "has model names for all built in LLMs" do
    expect(Raif.available_llm_keys.sort).to eq(I18n.t("raif.model_names").keys.sort)

    Raif.default_llms.values.flatten.each do |llm_config|
      llm = Raif.llm(llm_config[:key])
      expect(llm.name).to_not include("Translation missing")
    end
  end
end
