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

  # Recursion is limited to keywords whose values are themselves schemas.
  # Everything else -- `enum`, `const`, `default`, `examples`, `description` --
  # is instance data or an annotation and is copied through untouched: an
  # object-valued `enum` entry that happens to look like a schema is a literal
  # the caller expects back verbatim, and rewriting it would change which values
  # the schema accepts. Descending only where schemas can appear also means an
  # unrecognized keyword is left alone, which risks a provider 400 rather than a
  # silently altered schema.
  SCHEMA_MAP_KEYWORDS = %w[properties patternProperties $defs definitions].freeze
  SCHEMA_ARRAY_KEYWORDS = %w[allOf anyOf oneOf prefixItems].freeze
  SCHEMA_KEYWORDS = %w[additionalItems additionalProperties contains else if not propertyNames then unevaluatedItems unevaluatedProperties].freeze

  def sanitize_structured_output_schema(schema)
    return schema unless schema.is_a?(Hash)

    sanitize_schema_node(schema)
  end

private

  def sanitize_schema_node(node)
    return node unless node.is_a?(Hash)

    unsupported = unsupported_schema_constraints_for(node)

    node.each_with_object({}) do |(key, value), sanitized|
      keyword = key.to_s
      next if unsupported.include?(keyword)
      next if keyword == "minItems" && unsupported_min_items?(node, value)

      sanitized[key] = sanitize_schema_keyword_value(keyword, value)
    end
  end

  def sanitize_schema_keyword_value(keyword, value)
    if SCHEMA_MAP_KEYWORDS.include?(keyword) && value.is_a?(Hash)
      value.transform_values { |subschema| sanitize_schema_node(subschema) }
    elsif SCHEMA_ARRAY_KEYWORDS.include?(keyword) && value.is_a?(Array)
      value.map { |subschema| sanitize_schema_node(subschema) }
    elsif SCHEMA_KEYWORDS.include?(keyword) || keyword == "items"
      # `items` takes either a single schema or, in tuple form, an array of them.
      value.is_a?(Array) ? value.map { |subschema| sanitize_schema_node(subschema) } : sanitize_schema_node(value)
    else
      value
    end
  end

  # Which constraints are rejected depends on the node's declared `type`:
  # `minLength` on a string is fine, `minimum` on the same node would not be.
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
