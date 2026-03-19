# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::StreamingResponses::Bedrock, type: :model do
  subject(:streaming_response) { described_class.new }

  let(:llm_key) { :test_bedrock_streaming_llm }
  let(:llm_api_name) { "test-bedrock-model" }
  let(:llm) { Raif::Llms::Bedrock.new(key: llm_key, api_name: llm_api_name) }

  before do
    allow(Raif.config).to receive(:llm_api_requests_enabled).and_return(true)
    allow(Raif.config).to receive(:bedrock_models_enabled).and_return(true)
    Raif.register_llm(Raif::Llms::Bedrock, key: llm_key, api_name: llm_api_name)
  end

  after do
    Raif.llm_registry.delete(llm_key)
  end

  def process_event(event)
    streaming_response.process_streaming_event(event.event_type, event)
  end

  def message_start_event
    Aws::BedrockRuntime::Types::MessageStartEvent.new(role: "assistant", event_type: :message_start)
  end

  def content_block_start_event(index:, start: Aws::BedrockRuntime::Types::ContentBlockStart::Unknown.new(unknown: "text"))
    Aws::BedrockRuntime::Types::ContentBlockStartEvent.new(
      start: start,
      content_block_index: index,
      event_type: :content_block_start
    )
  end

  def text_delta_event(index:, text:)
    Aws::BedrockRuntime::Types::ContentBlockDeltaEvent.new(
      delta: Aws::BedrockRuntime::Types::ContentBlockDelta::Text.new(text: text),
      content_block_index: index,
      event_type: :content_block_delta
    )
  end

  def reasoning_text_delta_event(index:, text:)
    Aws::BedrockRuntime::Types::ContentBlockDeltaEvent.new(
      delta: Aws::BedrockRuntime::Types::ContentBlockDelta::ReasoningContent.new(
        reasoning_content: Aws::BedrockRuntime::Types::ReasoningContentBlockDelta::Text.new(text: text)
      ),
      content_block_index: index,
      event_type: :content_block_delta
    )
  end

  def reasoning_signature_delta_event(index:, signature:)
    Aws::BedrockRuntime::Types::ContentBlockDeltaEvent.new(
      delta: Aws::BedrockRuntime::Types::ContentBlockDelta::ReasoningContent.new(
        reasoning_content: Aws::BedrockRuntime::Types::ReasoningContentBlockDelta::Signature.new(signature: signature)
      ),
      content_block_index: index,
      event_type: :content_block_delta
    )
  end

  def reasoning_redacted_delta_event(index:, redacted_content:)
    Aws::BedrockRuntime::Types::ContentBlockDeltaEvent.new(
      delta: Aws::BedrockRuntime::Types::ContentBlockDelta::ReasoningContent.new(
        reasoning_content: Aws::BedrockRuntime::Types::ReasoningContentBlockDelta::RedactedContent.new(redacted_content: redacted_content)
      ),
      content_block_index: index,
      event_type: :content_block_delta
    )
  end

  def tool_use_start_event(index:, tool_use_id:, name:)
    Aws::BedrockRuntime::Types::ContentBlockStartEvent.new(
      start: Aws::BedrockRuntime::Types::ContentBlockStart::ToolUse.new(
        tool_use: Aws::BedrockRuntime::Types::ToolUseBlockStart.new(tool_use_id: tool_use_id, name: name)
      ),
      content_block_index: index,
      event_type: :content_block_start
    )
  end

  def tool_use_delta_event(index:, input:)
    Aws::BedrockRuntime::Types::ContentBlockDeltaEvent.new(
      delta: Aws::BedrockRuntime::Types::ContentBlockDelta::ToolUse.new(
        tool_use: Aws::BedrockRuntime::Types::ToolUseBlockDelta.new(input: input)
      ),
      content_block_index: index,
      event_type: :content_block_delta
    )
  end

  def content_block_stop_event(index:)
    Aws::BedrockRuntime::Types::ContentBlockStopEvent.new(content_block_index: index, event_type: :content_block_stop)
  end

  def message_stop_event(stop_reason: "end_turn")
    Aws::BedrockRuntime::Types::MessageStopEvent.new(stop_reason: stop_reason, event_type: :message_stop)
  end

  def model_completion_for(target_llm = llm)
    Raif::ModelCompletion.new(
      messages: [{ "role" => "user", "content" => [{ "text" => "Hello" }] }],
      llm_model_key: target_llm.key.to_s,
      model_api_name: target_llm.api_name
    )
  end

  it "preserves reasoning blocks while streaming visible text deltas" do
    process_event(message_start_event)
    process_event(content_block_start_event(index: 0))

    delta, finish_reason = process_event(reasoning_text_delta_event(index: 0, text: "internal reasoning"))
    expect(delta).to be_nil
    expect(finish_reason).to be_nil

    process_event(reasoning_signature_delta_event(index: 0, signature: "sig-123"))
    process_event(content_block_stop_event(index: 0))
    process_event(content_block_start_event(index: 1))

    delta, finish_reason = process_event(text_delta_event(index: 1, text: "Visible answer"))
    expect(delta).to eq("Visible answer")
    expect(finish_reason).to be_nil

    process_event(content_block_stop_event(index: 1))
    process_event(message_stop_event)

    response = streaming_response.current_response
    reasoning_text = response.output.message.content[0].reasoning_content.reasoning_text

    expect(reasoning_text.text).to eq("internal reasoning")
    expect(reasoning_text.signature).to eq("sig-123")
    expect(response.output.message.content[1].text).to eq("Visible answer")

    model_completion = model_completion_for
    llm.send(:update_model_completion, model_completion, response)

    expect(model_completion.raw_response).to eq("Visible answer")
    expect(model_completion.response_tool_calls).to be_nil
  end

  it "preserves reasoning blocks alongside tool use blocks" do
    process_event(message_start_event)
    process_event(content_block_start_event(index: 0))
    process_event(reasoning_text_delta_event(index: 0, text: "internal reasoning"))
    process_event(content_block_stop_event(index: 0))
    process_event(tool_use_start_event(index: 1, tool_use_id: "tooluse_123", name: "fetch_url"))
    process_event(tool_use_delta_event(index: 1, input: '{"url":"https://example.com"}'))
    process_event(content_block_stop_event(index: 1))

    tool_calls = llm.extract_response_tool_calls(streaming_response.current_response)

    expect(tool_calls).to eq([{
      "provider_tool_call_id" => "tooluse_123",
      "name" => "fetch_url",
      "arguments" => { "url" => "https://example.com" }
    }])
  end

  it "preserves reasoning-only redacted blocks without turning them into assistant text" do
    process_event(message_start_event)
    process_event(content_block_start_event(index: 0))

    delta, finish_reason = process_event(reasoning_redacted_delta_event(index: 0, redacted_content: "ciphertext"))
    expect(delta).to be_nil
    expect(finish_reason).to be_nil

    process_event(content_block_stop_event(index: 0))

    response = streaming_response.current_response
    expect(response.output.message.content[0].reasoning_content.redacted_content).to eq("ciphertext")

    model_completion = model_completion_for
    llm.send(:update_model_completion, model_completion, response)

    expect(model_completion.raw_response).to be_nil
    expect(model_completion.response_tool_calls).to be_nil
  end
end
