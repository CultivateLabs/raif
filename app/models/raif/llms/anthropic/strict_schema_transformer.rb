# frozen_string_literal: true

class Raif::Llms::Anthropic::StrictSchemaTransformer
  # Anthropic's strict schema subset rejects these validation constraints.
  # They are removed from the wire schema and folded into the property's
  # description so the model still sees them. The caller's original schema
  # remains unchanged and can still be used locally.
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
    uniqueItems
    minProperties
    maxProperties
    patternProperties
  ].freeze

  # The strict subset does support minItems values of 0 and 1, so instead of
  # dropping the constraint entirely, larger bounds are clamped to 1 -- the
  # API then rejects empty arrays via constrained decoding, and the real
  # bound rides in the description and the caller's local validation.
  WIRE_MIN_ITEMS_MAX = 1

  DATA_VALUE_KEYS = %w[enum const default examples].freeze
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
    transformed = {}
    notes = []

    schema.each do |key, value|
      key_string = key.to_s

      if key_string == "contains"
        raise Raif::Errors::UnsupportedFeatureError,
          "Anthropic structured outputs do not support contains, and Raif cannot enforce it locally"
      elsif key_string == "minItems"
        clamped = clamp_min_items(value)
        transformed[key] = clamped unless clamped.nil?
      elsif UNSUPPORTED_KEYS.include?(key_string)
        notes << constraint_note(schema, key_string, value)
      else
        transformed[key] = transform_schema_value(key, value)
      end
    end

    notes.concat(item_count_notes(schema))
    append_description_notes(transformed, notes.compact)
    transformed
  end

  def transform_schema_value(key, value)
    return value if DATA_VALUE_KEYS.include?(key.to_s)
    return transform_name_map(value) if schema_name_map?(key, value)

    transform(value)
  end

  def schema_name_map?(key, value)
    SCHEMA_NAME_MAP_KEYS.include?(key.to_s) && value.is_a?(Hash)
  end

  def transform_name_map(name_map)
    name_map.transform_values { |subschema| transform(subschema) }
  end

  def clamp_min_items(value)
    value = integer_constraint_value(value)
    return if value.nil? || value.negative?

    [value, WIRE_MIN_ITEMS_MAX].min
  end

  def item_count_notes(schema)
    min_items = constraint_value(schema, "minItems")
    max_items = constraint_value(schema, "maxItems")

    if min_items && min_items == max_items
      [format_item_count_note("exactly", min_items)]
    else
      notes = []
      notes << format_item_count_note("at least", min_items) if min_items && min_items > WIRE_MIN_ITEMS_MAX
      notes << format_item_count_note("at most", max_items) if max_items
      notes
    end
  end

  def format_item_count_note(qualifier, count)
    "Must contain #{qualifier} #{count} #{count == 1 ? "item" : "items"}."
  end

  def constraint_value(schema, key)
    integer_constraint_value(schema_value(schema, key))
  end

  def constraint_note(schema, key, value)
    case key
    when "minimum"
      numeric_note("at least", value) unless draft_4_exclusive?(schema, "exclusiveMinimum")
    when "maximum"
      numeric_note("at most", value) unless draft_4_exclusive?(schema, "exclusiveMaximum")
    when "exclusiveMinimum"
      exclusive_note("greater than", value, schema_value(schema, "minimum"))
    when "exclusiveMaximum"
      exclusive_note("less than", value, schema_value(schema, "maximum"))
    when "multipleOf"
      "Must be a multiple of #{value}." if value.is_a?(Numeric)
    when "minLength"
      length_note("at least", value)
    when "maxLength"
      length_note("at most", value)
    when "pattern"
      "Must match the pattern /#{value}/." if value.is_a?(String)
    when "uniqueItems"
      "Items must be unique." if value == true
    when "minProperties"
      count_note("at least", value, "property")
    when "maxProperties"
      count_note("at most", value, "property")
    when "patternProperties"
      pattern_properties_note(value)
    end
  end

  def draft_4_exclusive?(schema, key)
    schema_value(schema, key) == true
  end

  def exclusive_note(qualifier, value, draft_4_bound)
    bound = value == true ? draft_4_bound : value
    numeric_note(qualifier, bound)
  end

  def numeric_note(qualifier, value)
    "Must be #{qualifier} #{value}." if value.is_a?(Numeric)
  end

  def count_note(qualifier, value, noun)
    count = integer_constraint_value(value)
    return unless count

    "Must contain #{qualifier} #{count} #{count == 1 ? noun : noun.pluralize}."
  end

  def length_note(qualifier, value)
    count = integer_constraint_value(value)
    return unless count

    "Must be #{qualifier} #{count} #{count == 1 ? "character" : "characters"} long."
  end

  def pattern_properties_note(value)
    return unless value.is_a?(Hash)

    value.map do |pattern, subschema|
      "Properties matching /#{pattern}/ must satisfy #{JSON.generate(subschema)}."
    end.join(" ")
  end

  def integer_constraint_value(value)
    return unless value.is_a?(Numeric) && value.to_i == value

    value.to_i
  end

  def schema_value(schema, key)
    return schema[key.to_sym] if schema.key?(key.to_sym)

    schema[key]
  end

  def append_description_notes(transformed, notes)
    return if notes.empty?

    key = description_key(transformed)
    transformed[key] = [transformed[key], *notes].compact.reject { |part| part.to_s.empty? }.join(" ")
  end

  def description_key(hash)
    return :description if hash.key?(:description)
    return "description" if hash.key?("description")

    hash.keys.first.is_a?(String) ? "description" : :description
  end
end
