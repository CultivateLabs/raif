# frozen_string_literal: true

module Raif::Concerns::Llms::OpenAiCompletions::Streaming
  extend ActiveSupport::Concern

private

  def streaming_chunk_handler(model_completion, &block)
    return unless model_completion.stream_response?

    streaming_response = StreamingResponse.new
    event_parser = EventStreamParser::Parser.new
    accumulated_delta = ""

    proc do |chunk, _size, _env|
      event_parser.feed(chunk) do |_type, data, _id, _reconnect_time|
        if data == "[DONE]"
          update_model_completion(model_completion, streaming_response.current_response_json)
          next
        end

        parsed_event = JSON.parse(data)
        delta, finish_reason = streaming_response.process_sse(parsed_event)

        accumulated_delta += delta if delta.present?

        if accumulated_delta.length >= Raif.config.streaming_update_chunk_size_threshold || finish_reason.present?
          update_model_completion(model_completion, streaming_response.current_response_json)

          if accumulated_delta.present?
            block.call(model_completion, accumulated_delta, parsed_event)
            accumulated_delta = ""
          end
        end
      end
    end
  end

  # This class will accumulate the response from the streaming chunks
  class StreamingResponse
    attr_reader :raw_response, :tool_calls

    def initialize
      @id = nil
      @raw_response = ""
      @tool_calls = []
      @usage = {}
      @finish_reason = nil
      @response_json = {}
    end

    def process_sse(event)
      @id ||= event["id"]
      delta_chunk = event.dig("choices", 0, "delta")
      finish_reason = event.dig("choices", 0, "finish_reason")
      @finish_reason ||= finish_reason

      delta_content = delta_chunk&.dig("content")
      @raw_response += delta_content if delta_content

      if delta_chunk&.key?("tool_calls")
        delta_chunk["tool_calls"].each do |tool_call_chunk|
          index = tool_call_chunk["index"]
          @tool_calls[index] ||= { "function" => {} }
          @tool_calls[index]["id"] ||= tool_call_chunk["id"]
          if tool_call_chunk.dig("function", "name")
            @tool_calls[index]["function"]["name"] = tool_call_chunk.dig("function", "name")
          end
          if tool_call_chunk.dig("function", "arguments")
            @tool_calls[index]["function"]["arguments"] ||= ""
            @tool_calls[index]["function"]["arguments"] += tool_call_chunk.dig("function", "arguments")
          end
        end
      end

      if event["usage"]
        @usage = event["usage"]
      end

      [delta_content, finish_reason]
    end

    def current_response_json
      message = {
        "role" => "assistant",
        "content" => @raw_response
      }

      if @tool_calls.any?
        message["content"] = nil # Per OpenAI spec, content is null if tool_calls are present
        message["tool_calls"] = @tool_calls.map do |tc|
          # The streaming format for tool calls is slightly different from the final format.
          # We need to adjust it here.
          {
            "id" => tc["id"],
            "type" => "function",
            "function" => {
              "name" => tc.dig("function", "name"),
              "arguments" => tc.dig("function", "arguments")
            }
          }
        end
      end

      {
        "id" => @id,
        "choices" => [{
          "index" => 0,
          "message" => message,
          "finish_reason" => @finish_reason
        }],
        "usage" => @usage
      }
    end
  end
end
