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
  ].freeze

  CONSTRAINT_NOTES = {
    "minimum" => ->(value) { "Must be at least #{value}." },
    "maximum" => ->(value) { "Must be at most #{value}." },
    "exclusiveMinimum" => ->(value) { "Must be greater than #{value}." },
    "exclusiveMaximum" => ->(value) { "Must be less than #{value}." },
    "multipleOf" => ->(value) { "Must be a multiple of #{value}." },
    "minLength" => ->(value) { "Must be at least #{value} characters long." },
    "maxLength" => ->(value) { "Must be at most #{value} characters long." },
    "pattern" => ->(value) { "Must match the pattern /#{value}/." }
  }.freeze

  # The strict subset does support minItems values of 0 and 1, so instead of
  # dropping the constraint entirely, larger bounds are clamped to 1 -- the
  # API then rejects empty arrays via constrained decoding, and the real
  # bound rides in the description and the caller's local validation.
  WIRE_MIN_ITEMS_MAX = 1

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

      if key_string == "minItems"
        clamped = clamp_min_items(value)
        transformed[key] = clamped unless clamped.nil?
      elsif UNSUPPORTED_KEYS.include?(key_string)
        notes << CONSTRAINT_NOTES[key_string]&.call(value)
      else
        transformed[key] = transform_schema_value(key, value)
      end
    end

    notes.concat(item_count_notes(schema))
    append_description_notes(transformed, notes.compact)
    transformed
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

  def clamp_min_items(value)
    return unless value.is_a?(Integer) && value >= 0

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
    value = schema[key.to_sym] || schema[key]
    value if value.is_a?(Integer)
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
