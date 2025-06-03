# frozen_string_literal: true

module Raif::Concerns::Llms::OpenAi::JsonSchemaValidation
  extend ActiveSupport::Concern

  def validate_json_schema!(schema)
    return if schema.blank?

    errors = []

    # Check if schema is present
    if schema.blank?
      errors << "JSON schema must include a 'schema' property"
    else
      # Check root object type
      if schema[:type] != "object" && !schema.key?(:properties)
        errors << "Root schema must be of type 'object' with 'properties'"
      end

      # Check all objects in the schema recursively
      validate_object_properties(schema, errors)

      # Check properties count (max 100 total)
      validate_properties_count(schema, errors)

      # Check nesting depth (max 5 levels)
      validate_nesting_depth(schema, errors)

      # Check for unsupported anyOf at root level
      if schema[:anyOf].present? && schema[:properties].blank?
        errors << "Root objects cannot be of type 'anyOf'"
      end
    end

    # Raise error if any validation issues found
    if errors.any?
      error_message = "Invalid JSON schema for OpenAI structured outputs: #{errors.join("; ")}\nSchema was: #{schema.inspect}"
      raise Raif::Errors::OpenAi::JsonSchemaError, error_message
    else
      true
    end
  end

private

  def validate_object_properties(schema, errors)
    return unless schema.is_a?(Hash)

    # Check if the current schema is an object and validate additionalProperties and required fields
    if schema[:type] == "object"
      if schema[:additionalProperties] != false
        errors << "All objects must have 'additionalProperties' set to false"
      end

      # Check that all properties are required
      if schema[:properties].is_a?(Hash) && schema[:properties].any?
        property_keys = schema[:properties].keys
        required_fields = schema[:required] || []

        if required_fields.sort != property_keys.map(&:to_s).sort
          errors << "All object properties must be listed in the 'required' array"
        end
      end
    end

    # Check if the current schema is an object and validate additionalProperties
    if schema[:type] == "object"
      if schema[:additionalProperties] != false
        errors << "All objects must have 'additionalProperties' set to false"
      end

      # Check properties of the object recursively
      if schema[:properties].is_a?(Hash)
        schema[:properties].each_value do |property|
          validate_object_properties(property, errors)
        end
      end
    end

    # Check array items
    if schema[:type] == "array" && schema[:items].is_a?(Hash)
      validate_object_properties(schema[:items], errors)
    end

    # Check anyOf
    if schema[:anyOf].is_a?(Array)
      schema[:anyOf].each do |option|
        validate_object_properties(option, errors)
      end
    end
  end

  def validate_properties_count(schema, errors, count = 0)
    return count unless schema.is_a?(Hash)

    if schema[:properties].is_a?(Hash)
      count += schema[:properties].size

      if count > 100
        errors << "Schema exceeds maximum of 100 total object properties"
        return count
      end

      # Check nested properties
      schema[:properties].each_value do |property|
        count = validate_properties_count(property, errors, count)
      end
    end

    # Check array items
    if schema[:type] == "array" && schema[:items].is_a?(Hash)
      count = validate_properties_count(schema[:items], errors, count)
    end

    count
  end

  def validate_nesting_depth(schema, errors, depth = 1)
    return unless schema.is_a?(Hash)

    if depth > 5
      errors << "Schema exceeds maximum nesting depth of 5 levels"
      return
    end

    if schema[:properties].is_a?(Hash)
      schema[:properties].each_value do |property|
        validate_nesting_depth(property, errors, depth + 1)
      end
    end

    # Check array items
    if schema[:type] == "array" && schema[:items].is_a?(Hash)
      validate_nesting_depth(schema[:items], errors, depth + 1)
    end
  end

end
