# frozen_string_literal: true

module Raif
  module Concerns
    module JsonSchemaDefinition
      extend ActiveSupport::Concern

      class_methods do
        def json_schema_definition(schema_name, &block)
          raise ArgumentError, "A block must be provided to define the JSON schema" unless block_given?

          # Check if block expects an instance parameter (arity == 1)
          # arity == 0: no parameters (class-level schema)
          # arity == 1: one parameter (instance-dependent schema)
          if block.arity == 1
            # Store block for instance-dependent schema building
            @schema_blocks ||= {}
            @schema_blocks[schema_name] = block
          else
            # Build schema immediately for class-level (backward compatible)
            @schemas ||= {}
            @schemas[schema_name] = Raif::JsonSchemaBuilder.new
            @schemas[schema_name].instance_eval(&block)
          end
        end

        def schema_defined?(schema_name)
          @schemas&.dig(schema_name).present? || @schema_blocks&.dig(schema_name).present?
        end

        def schema_for(schema_name)
          # Check if this is an instance-dependent schema
          if @schema_blocks&.dig(schema_name).present?
            raise Raif::Errors::InstanceDependentSchemaError,
              "The schema '#{schema_name}' is instance-dependent and cannot be accessed at the class level. " \
                "Call this method on an instance instead."
          end

          @schemas[schema_name].to_schema
        end

        def instance_dependent_schema?(schema_name)
          @schema_blocks&.dig(schema_name).present?
        end
      end

      # Instance method to build schema with instance context
      def schema_for_instance(schema_name)
        block = self.class.instance_variable_get(:@schema_blocks)&.[](schema_name)

        if block
          # Build schema with instance context
          builder = Raif::JsonSchemaBuilder.new
          builder.build_with_instance(self, &block)
          builder.to_schema
        elsif self.class.schema_defined?(schema_name)
          # Fall back to class-level schema
          self.class.schema_for(schema_name)
        end
      end
    end
  end
end
