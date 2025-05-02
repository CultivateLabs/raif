# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Llm, type: :model do
  describe "#chat" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:system_prompt) { "You are a helpful assistant." }

    let(:test_llm) do
      Raif::Llms::Test.new(key: :raif_test_llm, api_name: "test_api")
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

  it "has model names for all built in LLMs" do
    Raif.default_llms.values.flatten.each do |llm_config|
      llm = Raif.llm(llm_config[:key])
      expect(llm.name).to_not include("Translation missing")
    end
  end
end
