# frozen_string_literal: true

module Raif::Concerns::Llms::Bedrock::Streaming
  extend ActiveSupport::Concern

private

  def streaming_chunk_handler(model_completion, &block)
    return unless model_completion.stream_response?

    streaming_response = StreamingResponse.new
    accumulated_delta = ""

    proc do |event|
      delta, finish_reason = streaming_response.process_event(event)
      accumulated_delta += delta if delta.present?

      if accumulated_delta.length >= Raif.config.streaming_update_chunk_size_threshold || finish_reason.present?
        update_model_completion(model_completion, streaming_response.current_response)

        if accumulated_delta.present?
          block.call(model_completion, accumulated_delta, event)
          accumulated_delta = ""
        end
      end
    end
  end

  class StreamingResponse
    def initialize_new_message
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

    def process_event(event)
      delta = nil
      puts "EVENT: #{event.event_type} -  #{event.inspect}"

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
        end
      when :content_block_stop
        content_block = @message.content[event.content_block_index]

        if content_block&.tool_use&.input.is_a?(String)
          begin
            content_block.tool_use.input = JSON.parse(content_block.tool_use.input)
          rescue JSON::ParserError
            # If parsing fails, leave as a string
          end
        end
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
  end
end
