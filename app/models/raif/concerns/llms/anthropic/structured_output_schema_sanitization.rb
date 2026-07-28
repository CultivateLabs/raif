# frozen_string_literal: true

# Anthropic's native structured-output validator accepts a narrower slice of
# JSON Schema than tool `input_schema` does, and rejects the whole request with
# a 400 when it sees a constraint outside that slice (e.g. "For 'integer' type,
# properties maximum, minimum are not supported"). Schemas written for the
# tool-call path therefore have to be stripped before they can be sent as
# `output_config`.
#
# Offending constraints are dropped rather than raising, which is what
# Anthropic's own SDKs do: structure, `required`, and enums are still enforced
# provider-side, and value-range checks belong in the caller's response
# validation either way (the tool-call path never enforced them).
#
# Included by Raif::Llms::Bedrock as well, whose Converse structured outputs
# serve the same Anthropic models.
module Raif::Concerns::Llms::Anthropic::StructuredOutputSchemaSanitization
  extend ActiveSupport::Concern

  UNSUPPORTED_CONSTRAINTS_BY_TYPE = {
    "integer" => %w[minimum maximum exclusiveMinimum exclusiveMaximum multipleOf],
    "number" => %w[minimum maximum exclusiveMinimum exclusiveMaximum multipleOf],
    "array" => %w[maxItems uniqueItems],
    "object" => %w[minProperties maxProperties]
  }.freeze

  # `minItems` is the one numeric constraint that survives, and only when it
  # says "possibly empty" (0) or "non-empty" (1). Any other bound is rejected.
  SUPPORTED_MIN_ITEMS_VALUES = [0, 1].freeze

  def sanitize_structured_output_schema(schema)
    sanitize_schema_node(schema)
  end

private

  def sanitize_schema_node(node)
    case node
    when Hash
      sanitize_schema_hash(node)
    when Array
      node.map { |element| sanitize_schema_node(element) }
    else
      node
    end
  end

  def sanitize_schema_hash(node)
    unsupported = unsupported_schema_constraints_for(node)

    node.each_with_object({}) do |(key, value), sanitized|
      next if unsupported.include?(key.to_s)
      next if key.to_s == "minItems" && unsupported_min_items?(node, value)

      sanitized[key] = sanitize_schema_node(value)
    end
  end

  # Keyed off the node's declared `type`, so a *property named* "minimum" or
  # "maxItems" inside a `properties` hash is left alone -- that hash's "type"
  # entry, if any, is a subschema rather than a type name.
  def unsupported_schema_constraints_for(node)
    type = schema_node_type(node)
    return [] if type.nil?

    UNSUPPORTED_CONSTRAINTS_BY_TYPE.fetch(type, [])
  end

  def unsupported_min_items?(node, value)
    return false unless schema_node_type(node) == "array"

    !SUPPORTED_MIN_ITEMS_VALUES.include?(value)
  end

  def schema_node_type(node)
    type = node[:type] || node["type"]
    return unless type.is_a?(String) || type.is_a?(Symbol)

    type.to_s
  end
end
