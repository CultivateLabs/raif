# frozen_string_literal: true

module Raif
  class JsonSchemaBuilder
    attr_reader :properties, :required_properties, :items_schema

    def initialize
      @properties = {}
      @required_properties = []
      @items_schema = nil
    end

    # Build schema with instance context for instance-dependent schemas
    # The block receives the instance as a parameter and has access to the builder methods
    #
    # @param instance [Object] The instance to use as context
    # @param block [Proc] The block to evaluate with instance context
    # @return [JsonSchemaBuilder] self for chaining
    def build_with_instance(instance, &block)
      # Evaluate the block in the context of the builder, passing the instance as parameter
      # This allows the block to use both builder methods (string, integer, etc.)
      # and access the instance parameter for conditional logic
      instance_exec(instance, &block)
      self
    end

    def string(name, options = {})
      add_property(name, "string", options)
    end

    def integer(name, options = {})
      add_property(name, "integer", options)
    end

    def number(name, options = {})
      add_property(name, "number", options)
    end

    def boolean(name, options = {})
      add_property(name, "boolean", options)
    end

    def object(name = nil, options = {}, &block)
      schema = {}

      if block_given?
        nested_builder = self.class.new
        nested_builder.instance_eval(&block)

        schema[:properties] = nested_builder.properties
        schema[:additionalProperties] = false

        # We currently use strict mode, which means that all properties are required
        schema[:required] = nested_builder.required_properties
      end

      # If name is nil, we're inside an array and should return the schema directly
      if name.nil?
        @items_schema = { type: "object" }.merge(schema)
      else
        add_property(name, "object", options.merge(schema))
      end
    end

    def array(name, options = {}, &block)
      items_schema = options.delete(:items) || {}

      if block_given?
        nested_builder = self.class.new
        nested_builder.instance_eval(&block)

        # If items were directly set using the items method
        if nested_builder.items_schema.present?
          items_schema = nested_builder.items_schema
        # If there are properties defined, it's an object schema
        elsif nested_builder.properties.any?
          items_schema = {
            type: "object",
            properties: nested_builder.properties,
            additionalProperties: false
          }

          # We currently use strict mode, which means that all properties are required
          items_schema[:required] = nested_builder.required_properties
        end
      end

      options[:items] = items_schema unless items_schema.empty?
      add_property(name, "array", options)
    end

    # Allow setting array items directly
    def items(options = {})
      @items_schema = options
    end

    def to_schema
      {
        type: "object",
        additionalProperties: false,
        properties: @properties,
        required: @required_properties
      }
    end

  private

    def add_property(name, type, options = {})
      property = { type: type }

      # We currently use strict mode, which means that all properties are required
      @required_properties << name.to_s

      property.merge!(options)
      @properties[name] = property
    end
  end
end
