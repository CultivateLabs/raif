# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::StreamingResponses::Anthropic, type: :model do
  subject(:streaming_response) { described_class.new }

  let(:llm){ Raif.llm(:anthropic_claude_3_5_haiku) }

  before do
    allow(Raif.config).to receive(:llm_api_requests_enabled){ true }
  end

  def model_completion
    @model_completion ||= Raif::ModelCompletion.new(
      llm_model_key: "anthropic_claude_3_5_haiku",
      model_api_name: "claude-3-5-haiku-latest"
    )
  end

  def process_stream(stop_reason:)
    streaming_response.process_streaming_event("message_start", {
      "type" => "message_start",
      "message" => { "id" => "msg_123", "usage" => { "input_tokens" => 10 } }
    })
    streaming_response.process_streaming_event("content_block_start", {
      "type" => "content_block_start",
      "index" => 0,
      "content_block" => { "type" => "text", "text" => "" }
    })
    streaming_response.process_streaming_event("content_block_delta", {
      "type" => "content_block_delta",
      "index" => 0,
      "delta" => { "type" => "text_delta", "text" => "Hello" }
    })
    streaming_response.process_streaming_event("message_delta", {
      "type" => "message_delta",
      "delta" => { "stop_reason" => stop_reason },
      "usage" => { "output_tokens" => 5 }
    })
    streaming_response.process_streaming_event("message_stop", { "type" => "message_stop" })
  end

  it "preserves a max_tokens stop reason through message_stop so a truncated stream is flagged" do
    process_stream(stop_reason: "max_tokens")

    expect(streaming_response.current_response_json["stop_reason"]).to eq("max_tokens")

    llm.send(:update_model_completion, model_completion, streaming_response.current_response_json)
    expect(model_completion.response_finish_reason).to eq("max_tokens")
    expect(model_completion).to be_truncated
  end

  it "preserves a normal end_turn stop reason without flagging the stream as truncated" do
    process_stream(stop_reason: "end_turn")

    llm.send(:update_model_completion, model_completion, streaming_response.current_response_json)
    expect(model_completion.response_finish_reason).to eq("end_turn")
    expect(model_completion).not_to be_truncated
  end
end
