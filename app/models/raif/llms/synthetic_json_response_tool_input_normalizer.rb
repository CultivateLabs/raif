# frozen_string_literal: true

class Raif::Llms::SyntheticJsonResponseToolInputNormalizer
  def self.call(input:, schema:)
    new(input:, schema:).call
  end

  def initialize(input:, schema:)
    @input = input
    @schema = schema
  end

  def call
    return @input unless @input.is_a?(Hash)
    return @input if expected_keys.empty?

    valid_candidates.max_by { |candidate| matching_key_count(candidate) }
  end

private

  def valid_candidates
    candidates.filter_map do |candidate|
      prepared = prepare_candidate(candidate)
      prepared if schema_matching_candidate?(prepared)
    end
  end

  def candidates
    [@input, unwrapped_candidate, decoded_candidate].compact
  end

  def unwrapped_candidate
    candidate = @input["json_response"] || @input[:json_response]
    candidate if candidate.is_a?(Hash)
  end

  def decoded_candidate
    return unless @input.one?

    try_parse_json_object(@input.values.first)
  end

  def try_parse_json_object(value)
    return unless value.is_a?(String)

    parsed = JSON.parse(value)
    parsed if parsed.is_a?(Hash)
  rescue JSON::ParserError
    nil
  end

  def expected_keys
    @expected_keys ||= schema_properties.keys.map(&:to_s)
  end

  def schema_properties
    return {} if @schema.blank?

    properties = @schema[:properties] || @schema["properties"]
    properties.is_a?(Hash) ? properties : {}
  end

  def prepare_candidate(candidate)
    normalized = candidate.deep_stringify_keys
    return normalized unless additional_properties_forbidden?

    normalized.slice(*expected_keys)
  end

  def additional_properties_forbidden?
    @schema[:additionalProperties] == false || @schema["additionalProperties"] == false
  end

  def schema_matching_candidate?(candidate)
    matching_key_count(candidate).positive? && JSON::Validator.validate(@schema, candidate)
  end

  def matching_key_count(candidate)
    (candidate.keys & expected_keys).size
  end
end
