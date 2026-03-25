# frozen_string_literal: true

class Raif::StreamingResponses::Bedrock

  def initialize_new_message
    @reasoning_content_blocks = {}

    # Initialize empty AWS response object
    @message = Aws::BedrockRuntime::Types::Message.new(
      role: "assistant",
      content: []
    )

    @output = Aws::BedrockRuntime::Types::ConverseOutput::Message.new(message: @message)

    @usage = Aws::BedrockRuntime::Types::TokenUsage.new(
      input_tokens: 0,
      output_tokens: 0,
      total_tokens: 0
    )

    @response = Aws::BedrockRuntime::Types::ConverseResponse.new(
      output: @output,
      usage: @usage,
      stop_reason: nil
    )
  end

  def process_streaming_event(event_type, event)
    delta = nil

    case event.event_type
    when :message_start
      initialize_new_message
    when :content_block_start
      index = event.content_block_index

      if event.start.is_a?(Aws::BedrockRuntime::Types::ContentBlockStart::ToolUse)
        tool_use = event.start.tool_use
        @message.content[index] = Aws::BedrockRuntime::Types::ContentBlock.new(
          tool_use: Aws::BedrockRuntime::Types::ToolUseBlock.new(
            tool_use_id: tool_use.tool_use_id,
            name: tool_use.name,
            input: ""
          )
        )
      else
        @message.content[index] = Aws::BedrockRuntime::Types::ContentBlock::Text.new(text: "")
      end
    when :content_block_delta
      index = event.content_block_index

      if event.delta.is_a?(Aws::BedrockRuntime::Types::ContentBlockDelta::Text)
        @message.content[index] ||= Aws::BedrockRuntime::Types::ContentBlock::Text.new(text: "")
        delta = event.delta.text
        @message.content[index].text += delta
      elsif event.delta.is_a?(Aws::BedrockRuntime::Types::ContentBlockDelta::ToolUse)
        tool_use = event.delta.tool_use
        @message.content[index] ||= Aws::BedrockRuntime::Types::ContentBlock.new
        @message.content[index].tool_use ||= Aws::BedrockRuntime::Types::ToolUseBlock.new(
          tool_use_id: tool_use.tool_use_id,
          name: tool_use.name,
          input: ""
        )

        @message.content[index].tool_use.input += event.delta.tool_use.input
      elsif event.delta.is_a?(Aws::BedrockRuntime::Types::ContentBlockDelta::ReasoningContent)
        accumulate_reasoning_content(index, event.delta.reasoning_content)
      end
    when :content_block_stop
      index = event.content_block_index
      content_block = @message.content[index]

      if content_block&.tool_use&.input.is_a?(String)
        begin
          content_block.tool_use.input = JSON.parse(content_block.tool_use.input)
        rescue JSON::ParserError
          # If parsing fails, leave as a string
        end
      end

      finalize_reasoning_content(index)
    when :message_stop
      @response.stop_reason = event.stop_reason
    when :metadata
      @response.usage = event.usage if event.respond_to?(:usage)
    end

    [delta, @response.stop_reason]
  end

  def current_response
    @response
  end

private

  def accumulate_reasoning_content(index, reasoning_delta)
    reasoning_content = reasoning_content_for(index)
    reasoning_content[:seen] = true

    case reasoning_delta
    when Aws::BedrockRuntime::Types::ReasoningContentBlockDelta::Text
      reasoning_content[:text] << reasoning_delta.text.to_s
    when Aws::BedrockRuntime::Types::ReasoningContentBlockDelta::Signature
      reasoning_content[:signature] = reasoning_delta.signature
    when Aws::BedrockRuntime::Types::ReasoningContentBlockDelta::RedactedContent
      reasoning_content[:redacted_content] << reasoning_delta.redacted_content.to_s
    else
      reasoning_content[:unknown] = true
    end
  end

  def finalize_reasoning_content(index)
    reasoning_content = @reasoning_content_blocks.delete(index)
    return unless reasoning_content&.dig(:seen)

    @message.content[index] = Aws::BedrockRuntime::Types::ContentBlock::ReasoningContent.new(
      reasoning_content: build_reasoning_content(reasoning_content)
    )
  end

  def build_reasoning_content(reasoning_content)
    if reasoning_content[:text].blank? && reasoning_content[:signature].blank? && reasoning_content[:redacted_content].present?
      return Aws::BedrockRuntime::Types::ReasoningContentBlock::RedactedContent.new(
        redacted_content: reasoning_content[:redacted_content]
      )
    end

    Aws::BedrockRuntime::Types::ReasoningContentBlock::ReasoningText.new(
      reasoning_text: Aws::BedrockRuntime::Types::ReasoningTextBlock.new(
        text: reasoning_content[:text],
        signature: reasoning_content[:signature]
      )
    )
  end

  def reasoning_content_for(index)
    @reasoning_content_blocks[index] ||= {
      seen: false,
      text: +"",
      signature: nil,
      redacted_content: +"",
      unknown: false
    }
  end

end
