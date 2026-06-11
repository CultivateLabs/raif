# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::StreamingResponses::Google, type: :model do
  subject(:streaming_response) { described_class.new }

  let(:llm) { Raif.llm(:google_gemini_2_5_flash) }

  before do
    allow(Raif.config).to receive(:llm_api_requests_enabled).and_return(true)
    allow(Raif.config).to receive(:google_api_key) { ENV["GOOGLE_AI_API_KEY"] }
  end

  def model_completion
    @model_completion ||= Raif::ModelCompletion.new(
      llm_model_key: "google_gemini_2_5_flash",
      model_api_name: "gemini-2.5-flash"
    )
  end

  def streamed_chunk(text:, finish_reason: nil)
    candidate = { "content" => { "parts" => [{ "text" => text }] } }
    candidate["finishReason"] = finish_reason if finish_reason
    {
      "candidates" => [candidate],
      "usageMetadata" => { "promptTokenCount" => 10, "candidatesTokenCount" => 5, "totalTokenCount" => 15 }
    }
  end

  it "carries the finish reason into the accumulated response so a truncated stream is flagged" do
    streaming_response.process_streaming_event(nil, streamed_chunk(text: "Hello", finish_reason: "MAX_TOKENS"))

    expect(streaming_response.current_response_json.dig("candidates", 0, "finishReason")).to eq("MAX_TOKENS")

    llm.send(:update_model_completion, model_completion, streaming_response.current_response_json)
    expect(model_completion.response_finish_reason).to eq("MAX_TOKENS")
    expect(model_completion).to be_truncated
  end

  it "carries a normal finish reason without flagging the stream as truncated" do
    streaming_response.process_streaming_event(nil, streamed_chunk(text: "Hello", finish_reason: "STOP"))

    llm.send(:update_model_completion, model_completion, streaming_response.current_response_json)
    expect(model_completion.response_finish_reason).to eq("STOP")
    expect(model_completion).not_to be_truncated
  end
end
