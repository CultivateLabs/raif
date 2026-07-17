# frozen_string_literal: true

module Raif::Concerns::Llms::JsonResponseNormalization
  extend ActiveSupport::Concern

private

  # Models occasionally emit degenerate json_response tool inputs: the real
  # payload nested under a "json_response" key, or double-encoded as a JSON
  # string value. When a schema is available, pick the candidate carrying the
  # most schema properties; an input carrying none is treated as unusable so
  # extraction can fall back to text blocks (which sometimes hold the JSON
  # instead). Without a schema, the input passes through unchanged.
  def normalize_json_response_tool_input(input, schema)
    return input unless input.is_a?(Hash)

    candidates = [input]

    unwrapped = input["json_response"] || input[:json_response]
    candidates << unwrapped if unwrapped.is_a?(Hash)

    if input.size == 1
      decoded = try_parse_json_object(input.values.first)
      candidates << decoded if decoded
    end

    expected_keys = schema_property_names(schema)
    return input if expected_keys.empty?

    best = candidates.max_by { |candidate| (candidate.keys.map(&:to_s) & expected_keys).size }
    return best if best && best.keys.map(&:to_s).intersect?(expected_keys)

    nil
  end

  def schema_property_names(schema)
    return [] if schema.blank?

    properties = schema[:properties] || schema["properties"]
    return [] unless properties.is_a?(Hash)

    properties.keys.map(&:to_s)
  end

  def try_parse_json_object(value)
    return unless value.is_a?(String)

    parsed = JSON.parse(value)
    parsed.is_a?(Hash) ? parsed : nil
  rescue JSON::ParserError
    nil
  end
end
