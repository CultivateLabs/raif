# frozen_string_literal: true

module Raif::Concerns::Llms::Anthropic::Streaming
  extend ActiveSupport::Concern

private

  def streaming_chunk_handler(model_completion, &block)
    return unless model_completion.stream_response?

    streaming_response = StreamingResponse.new
    event_parser = EventStreamParser::Parser.new
    accumulated_delta = ""

    proc do |chunk, _size, _env|
      event_parser.feed(chunk) do |event_type, data, _id, _reconnect_time|
        next unless event_type && data

        event_data = JSON.parse(data)
        delta, finish_reason = streaming_response.process_sse(event_type, event_data)

        accumulated_delta += delta if delta.present?

        if accumulated_delta.length >= Raif.config.streaming_update_chunk_size_threshold || finish_reason.present?
          update_model_completion(model_completion, streaming_response.current_response_json)

          if accumulated_delta.present?
            block.call(model_completion, accumulated_delta, event_data)
            accumulated_delta = ""
          end
        end
      end
    end
  end

  class StreamingResponse
    def initialize
      @response_json = { "content" => [], "usage" => {} }
      @finish_reason = nil
    end

    def process_sse(event_type, event_data)
      delta = nil
      index = event_data["index"]

      case event_type
      when "message_start"
        @response_json = event_data["message"]
        @response_json["content"] = []
        @response_json["usage"] ||= {}
      when "content_block_start"
        @response_json["content"][index] = event_data["content_block"]
        if event_data.dig("content_block", "type") == "tool_use"
          @response_json["content"][index]["input"] = ""
        end
      when "content_block_delta"
        delta_chunk = event_data["delta"]
        if delta_chunk["type"] == "text_delta"
          delta = delta_chunk["text"]
          @response_json["content"][index]["text"] += delta if delta
        elsif delta_chunk["type"] == "input_json_delta"
          @response_json["content"][index]["input"] += delta_chunk["partial_json"]
        end
      when "content_block_stop"
        content_block = @response_json["content"][index]
        if content_block&.dig("type") == "tool_use"
          begin
            content_block["input"] = JSON.parse(content_block["input"])
          rescue JSON::ParserError
            # If parsing fails, leave as a string
          end
        end
      when "message_delta"
        @finish_reason = event_data.dig("delta", "stop_reason")
        @response_json["usage"]["output_tokens"] = event_data.dig("usage", "output_tokens")
      when "message_stop"
        @finish_reason = "stop"
      when "error"
        error_details = event_data["error"]
        raise Raif::Errors::StreamingError.new(
          message: error_details["message"],
          type: error_details["type"],
          event: event_data
        )
      end

      [delta, @finish_reason]
    end

    def current_response_json
      @response_json["stop_reason"] = @finish_reason
      @response_json
    end
  end
end
