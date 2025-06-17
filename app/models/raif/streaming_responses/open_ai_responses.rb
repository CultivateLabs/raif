# frozen_string_literal: true

class Raif::StreamingResponses::OpenAiResponses

  def initialize
    @output_items = []
    @finish_reason = nil
  end

  def process_streaming_event(event_type, event)
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
      @output_items[output_index]["content"][content_index]["text"] ||= ""
      @output_items[output_index]["content"][content_index]["text"] += event["delta"]
    when "response.output_text.done"
      @output_items[output_index]["content"][content_index]["text"] = event["text"]
    when "response.completed"
      @usage = event["response"]["usage"]
      @finish_reason = "stop"
    when "error"
      raise Raif::Errors::StreamingError.new(
        message: event["message"],
        type: event["type"],
        code: event["code"],
        event: event
      )
    end

    [delta, @finish_reason]
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
