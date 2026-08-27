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

  describe "part accumulation" do
    def function_call_part
      {
        "functionCall" => { "name" => "wikipedia_search", "args" => { "query" => "Prime Minister of Canada" }, "id" => "call_1" },
        "thoughtSignature" => "sig-abc"
      }
    end

    def chunk_with_parts(parts, finish_reason: nil)
      candidate = { "content" => { "parts" => parts } }
      candidate["finishReason"] = finish_reason if finish_reason
      { "candidates" => [candidate] }
    end

    def accumulated_parts
      streaming_response.current_response_json.dig("candidates", 0, "content", "parts")
    end

    it "appends consecutive text deltas into a single text part" do
      streaming_response.process_streaming_event(nil, streamed_chunk(text: "Hel"))
      streaming_response.process_streaming_event(nil, streamed_chunk(text: "lo", finish_reason: "STOP"))

      expect(accumulated_parts).to eq([{ "text" => "Hello" }])
    end

    # Mirrors the chunk sequence Gemini 3 models actually send for a tool call.
    it "keeps a function call when the finish chunk carries only an empty text part" do
      streaming_response.process_streaming_event(nil, chunk_with_parts([function_call_part]))
      streaming_response.process_streaming_event(nil, chunk_with_parts([{ "text" => "" }], finish_reason: "STOP"))

      expect(accumulated_parts).to eq([function_call_part])

      llm.send(:update_model_completion, model_completion, streaming_response.current_response_json)
      expect(model_completion.response_tool_calls.map { |call| call["name"] }).to eq(["wikipedia_search"])
      expect(model_completion.response_tool_calls.first["provider_metadata"]).to eq({ "thought_signature" => "sig-abc" })
    end

    it "keeps streamed text and a following function call as separate parts" do
      streaming_response.process_streaming_event(nil, streamed_chunk(text: "Let me look that up."))
      streaming_response.process_streaming_event(nil, chunk_with_parts([function_call_part], finish_reason: "STOP"))

      expect(accumulated_parts).to eq([{ "text" => "Let me look that up." }, function_call_part])

      llm.send(:update_model_completion, model_completion, streaming_response.current_response_json)
      expect(model_completion.raw_response).to eq("Let me look that up.")
      expect(model_completion.response_tool_calls.map { |call| call["name"] }).to eq(["wikipedia_search"])
    end

    it "starts a new text part for text that follows a function call" do
      streaming_response.process_streaming_event(nil, chunk_with_parts([function_call_part]))
      streaming_response.process_streaming_event(nil, streamed_chunk(text: "Searching now.", finish_reason: "STOP"))

      expect(accumulated_parts).to eq([function_call_part, { "text" => "Searching now." }])
    end
  end
end
