# frozen_string_literal: true

module Raif::Concerns::Llms::OpenAiResponses::Streaming
  extend ActiveSupport::Concern

private

  def streaming_chunk_handler(model_completion, &block)
    return unless model_completion.stream_response?

    streaming_response = StreamingResponse.new
    event_parser = EventStreamParser::Parser.new
    accumulated_delta = ""

    proc do |chunk, _size, _env|
      event_parser.feed(chunk) do |_type, data, _id, _reconnect_time|
        parsed_event = JSON.parse(data)
        delta = streaming_response.process_sse(parsed_event)

        accumulated_delta += delta if delta.is_a?(String)

        if accumulated_delta.length >= Raif.config.streaming_update_chunk_size_threshold || parsed_event["type"] == "response.completed"
          update_model_completion(model_completion, streaming_response.current_response_json)

          if accumulated_delta.present?
            block.call(model_completion, accumulated_delta, parsed_event)
            accumulated_delta = ""
          end
        end
      end
    end
  end

  class StreamingResponse
    def initialize
      @output_items = []
    end

    def process_sse(event)
      output_index = event["output_index"]
      content_index = event["content_index"]

      delta = nil

      case event["type"]
      when "response.created"
        @id = event["response"]["id"]
      when "response.output_item.added", "response.output_item.done"
        @output_items[output_index] = event["item"]
      when "response.content_part.added", "response.content_part.done"
        @output_items[output_index]["content"] ||= []
        @output_items[output_index]["content"][content_index] = event["part"]
      when "response.output_text.delta"
        delta = event["delta"]
        @output_items[output_index]["content"][content_index]["text"] += event["delta"]
      when "response.output_text.done"
        @output_items[output_index]["content"][content_index]["text"] = event["text"]
      when "response.completed"
        @usage = event["response"]["usage"]
      when "error"
        raise Raif::Errors::StreamingError.new(
          message: event["message"],
          type: event["type"],
          code: event["code"],
          event: event
        )
      end

      delta
    end

    # The response we've built up so far.
    def current_response_json
      {
        "id" => @id,
        "output" => @output_items,
        "usage" => @usage
      }
    end

  end
end
