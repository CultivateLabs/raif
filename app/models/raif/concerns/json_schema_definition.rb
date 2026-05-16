# frozen_string_literal: true

module Raif
  module Concerns
    module JsonSchemaDefinition
      extend ActiveSupport::Concern

      class_methods do
        def json_schema_definition(schema_name, dynamic: false, &block)
          raise ArgumentError, "A block must be provided to define the JSON schema" unless block_given?

          # Dispatch by arity × dynamic flag:
          #   - arity 1, dynamic: false → instance-dependent schema. `self` inside
          #     the block is the builder (so DSL methods work); the calling
          #     instance is passed as the block's single parameter. Used by
          #     e.g. Raif::Task subclasses to gate fields on their own state.
          #   - arity 1, dynamic: true  → source-aware dynamic schema. Same
          #     evaluation, but the block's parameter is the caller `source`
          #     (typically an agent). Re-evaluated on each read.
          #   - arity 0, dynamic: true  → dynamic schema re-evaluated on each
          #     read, no context passed in.
          #   - arity 0, dynamic: false → static class-level schema built once.
          if block.arity == 1 && !dynamic
            @schema_blocks ||= {}
            @schema_blocks[schema_name] = block
          elsif dynamic
            @dynamic_schema_blocks ||= {}
            @dynamic_schema_blocks[schema_name] = block
          else
            @schemas ||= {}
            @schemas[schema_name] = Raif::JsonSchemaBuilder.new
            @schemas[schema_name].instance_eval(&block)
          end
        end

        def schema_defined?(schema_name)
          @schemas&.dig(schema_name).present? ||
            @schema_blocks&.dig(schema_name).present? ||
            @dynamic_schema_blocks&.dig(schema_name).present?
        end

        # @param schema_name [Symbol] The schema to look up
        # @param source [Object, nil] Optional caller context (e.g. the agent or
        #   conversation triggering schema evaluation). Forwarded into dynamic
        #   schema blocks whose block accepts a single argument. Static schemas
        #   and arity-0 dynamic schemas ignore it.
        def schema_for(schema_name, source: nil)
          # Check if this is an instance-dependent schema
          if @schema_blocks&.dig(schema_name).present?
            raise Raif::Errors::InstanceDependentSchemaError,
              "The schema '#{schema_name}' is instance-dependent and cannot be accessed at the class level. " \
                "Call this method on an instance instead."
          end

          # Check if this is a dynamic schema (re-evaluate each call)
          if (block = @dynamic_schema_blocks&.dig(schema_name)).present?
            builder = Raif::JsonSchemaBuilder.new
            if block.arity == 1
              builder.instance_exec(source, &block)
            else
              builder.instance_eval(&block)
            end
            return builder.to_schema
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
          # Fall back to class-level schema (handles both static and dynamic)
          self.class.schema_for(schema_name)
        end
      end
    end
  end
end
