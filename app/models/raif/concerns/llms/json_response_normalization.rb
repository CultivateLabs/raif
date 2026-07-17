# frozen_string_literal: true

module Raif::Concerns::Llms::JsonResponseNormalization
  extend ActiveSupport::Concern

private

  # Models occasionally emit degenerate json_response tool inputs: the real
  # payload nested under a "json_response" key, or double-encoded as a JSON
  # string value. When a schema is available, remove unknown root properties if
  # the schema forbids them, then pick the valid candidate carrying the most
  # schema properties. If none satisfies the original schema, extraction can fall
  # back to text blocks (which sometimes hold the JSON instead). Without a schema,
  # the input passes through unchanged.
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

    candidates
      .map { |candidate| prepare_schema_candidate(candidate, schema, expected_keys) }
      .select { |candidate| schema_matching_candidate?(candidate, schema, expected_keys) }
      .max_by { |candidate| matching_key_count(candidate, expected_keys) }
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

  def schema_matching_candidate?(candidate, schema, expected_keys)
    matching_key_count(candidate, expected_keys).positive? && JSON::Validator.validate(schema, candidate)
  end

  def prepare_schema_candidate(candidate, schema, expected_keys)
    normalized = candidate.deep_stringify_keys
    return normalized unless additional_properties_forbidden?(schema)

    normalized.slice(*expected_keys)
  end

  def additional_properties_forbidden?(schema)
    schema[:additionalProperties] == false || schema["additionalProperties"] == false
  end

  def matching_key_count(candidate, expected_keys)
    (candidate.keys.map(&:to_s) & expected_keys).size
  end
end
