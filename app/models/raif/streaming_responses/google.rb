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

      # Check for finish reason
      @finish_reason = candidate["finishReason"] if candidate["finishReason"].present?

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

  def process_content_parts(parts)
    delta = nil

    parts.each_with_index do |part, index|
      if part.key?("text")
        delta = part["text"]
        accumulate_text_part(part, index)
      else
        # For non-text parts (e.g., functionCall), just store directly
        @response_json["candidates"][0]["content"]["parts"][index] = part
      end
    end

    delta
  end

  def accumulate_text_part(part, index)
    existing_part = @response_json.dig("candidates", 0, "content", "parts", index)

    if existing_part.present? && existing_part.key?("text")
      # Accumulate text from incremental chunks
      existing_part["text"] += part["text"]
    else
      # First text chunk for this index
      @response_json["candidates"][0]["content"]["parts"][index] = part.dup
    end
  end

end
