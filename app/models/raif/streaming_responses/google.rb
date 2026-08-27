# frozen_string_literal: true

class Raif::StreamingResponses::Google

  def initialize
    @response_json = { "candidates" => [{ "content" => { "parts" => [] } }], "usageMetadata" => {} }
    @finish_reason = nil
  end

  def process_streaming_event(event_type, event)
    delta = nil

    # Google streams complete candidate objects, so we need to extract the new text
    candidates = event["candidates"]
    if candidates.present?
      candidate = candidates[0]

      # Check for finish reason. Mirror it into the accumulated response JSON so
      # update_model_completion (which digs candidates/0/finishReason) sees it -
      # otherwise streamed completions would always persist a nil finish reason.
      if candidate["finishReason"].present?
        @finish_reason = candidate["finishReason"]
        @response_json["candidates"][0]["finishReason"] = @finish_reason
      end

      # Process content parts
      parts = candidate.dig("content", "parts")
      delta = process_content_parts(parts) if parts.present?
    end

    # Update usage metadata
    usage_metadata = event["usageMetadata"]
    @response_json["usageMetadata"] = usage_metadata if usage_metadata.present?

    [delta, @finish_reason]
  end

  def current_response_json
    @response_json
  end

private

  # Parts are accumulated in arrival order, not by their index within a chunk:
  # Gemini 3 sends a function call as parts[0] of one chunk and then a finish
  # chunk whose parts[0] is an empty text delta, which would overwrite the call.
  def process_content_parts(parts)
    delta = nil

    parts.each do |part|
      if part.key?("text")
        delta = part["text"]
        accumulate_text_part(part)
      else
        # functionCall parts arrive complete in one chunk because the request does
        # not opt into streamFunctionCallArguments; enabling that would require
        # accumulating partialArgs the way text is accumulated.
        accumulated_parts << part
      end
    end

    delta
  end

  def accumulate_text_part(part)
    last_part = accumulated_parts.last

    if last_part.present? && last_part.key?("text")
      last_part["text"] += part["text"]
    elsif !part["text"].empty?
      accumulated_parts << part.dup
    end
  end

  def accumulated_parts
    @response_json["candidates"][0]["content"]["parts"]
  end

end
