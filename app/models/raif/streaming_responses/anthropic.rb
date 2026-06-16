# frozen_string_literal: true

class Raif::StreamingResponses::Anthropic

  def initialize
    @response_json = { "content" => [], "usage" => {} }
    @finish_reason = nil
  end

  def process_streaming_event(event_type, event)
    delta = nil
    index = event["index"]

    case event_type
    when "message_start"
      @response_json = event["message"]
      @response_json["content"] = []
      @response_json["usage"] ||= {}
    when "content_block_start"
      @response_json["content"][index] = event["content_block"]
      if event.dig("content_block", "type") == "tool_use"
        @response_json["content"][index]["input"] = ""
      end
    when "content_block_delta"
      delta_chunk = event["delta"]
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
      @finish_reason = event.dig("delta", "stop_reason")
      @response_json["usage"]["output_tokens"] = event.dig("usage", "output_tokens")
    when "message_stop"
      # message_stop carries no stop_reason of its own and always follows the message_delta
      # that does - only default to the flush-sentinel when nothing was captured, so the
      # real reason (e.g. "max_tokens") survives into current_response_json.
      @finish_reason ||= "stop"
    when "error"
      error_details = event["error"]
      raise Raif::Errors::StreamingError.new(
        message: error_details["message"],
        type: error_details["type"],
        event: event
      )
    end

    [delta, @finish_reason]
  end

  def current_response_json
    @response_json["stop_reason"] = @finish_reason
    @response_json
  end

end
