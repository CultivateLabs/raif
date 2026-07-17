# frozen_string_literal: true

class Raif::Llms::Anthropic::StrictSchemaTransformer
  # Anthropic's strict schema subset rejects these validation constraints. The
  # caller's original schema remains unchanged and can still be used locally.
  UNSUPPORTED_KEYS = %w[
    minimum
    maximum
    exclusiveMinimum
    exclusiveMaximum
    multipleOf
    minLength
    maxLength
    minItems
    maxItems
    pattern
  ].freeze

  SCHEMA_NAME_MAP_KEYS = %w[properties $defs definitions].freeze

  def self.call(schema)
    new(schema).call
  end

  def initialize(schema)
    @schema = schema
  end

  def call
    transform(@schema)
  end

private

  def transform(value)
    case value
    when Hash then transform_hash(value)
    when Array then value.map { |item| transform(item) }
    else value
    end
  end

  def transform_hash(schema)
    schema.each_with_object({}) do |(key, value), transformed|
      next if UNSUPPORTED_KEYS.include?(key.to_s)

      transformed[key] = transform_schema_value(key, value)
    end
  end

  def transform_schema_value(key, value)
    return transform_name_map(value) if schema_name_map?(key, value)

    transform(value)
  end

  def schema_name_map?(key, value)
    SCHEMA_NAME_MAP_KEYS.include?(key.to_s) && value.is_a?(Hash)
  end

  def transform_name_map(name_map)
    name_map.transform_values { |subschema| transform(subschema) }
  end
end
