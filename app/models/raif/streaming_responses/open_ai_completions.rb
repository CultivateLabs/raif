# frozen_string_literal: true

class Raif::StreamingResponses::OpenAiCompletions
  attr_reader :raw_response, :tool_calls

  def initialize
    @id = nil
    @raw_response = ""
    @tool_calls = []
    @usage = {}
    @finish_reason = nil
    @response_json = {}
  end

  def process_streaming_event(event_type, event)
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

    @usage = event["usage"] if event["usage"]

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
