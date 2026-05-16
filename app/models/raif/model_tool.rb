# frozen_string_literal: true

class Raif::ModelTool
  include Raif::Concerns::JsonSchemaDefinition

  delegate :tool_name, :tool_description, :example_model_invocation, to: :class

  class << self
    # The description of the tool that will be provided to the model
    # when giving it a list of available tools.
    #
    # @param source [Object, nil] Optional caller context forwarded into any
    #   source-aware schema or example blocks.
    def description_for_llm(source: nil)
      <<~DESCRIPTION
        Name: #{tool_name}
        Description: #{tool_description}
        Arguments Schema:
        #{JSON.pretty_generate(tool_arguments_schema_for_source(source))}
        Example Usage:
        #{JSON.pretty_generate(example_model_invocation_for_source(source))}
      DESCRIPTION
    end

    # The name of the tool as it will be provided to the model & used in the model invocation.
    # Default for something like Raif::ModelTools::WikipediaSearch would be "wikipedia_search"
    def tool_name
      name.split("::").last.underscore
    end

    def tool_description(&block)
      if block_given?
        @tool_description = block.call
      elsif @tool_description.present?
        @tool_description
      else
        raise NotImplementedError, "#{name}#tool_description is not implemented"
      end
    end

    # Defines or retrieves the tool's example model invocation.
    #
    # Definition:
    #   - Arity-0 block: the block's return value is the example (evaluated lazily
    #     on first read, then cached).
    #   - Arity-1 block: receives the caller `source` on each read. Not cached,
    #     so the example can reflect per-run context.
    #
    # @param source [Object, nil] Passed into arity-1 example blocks; ignored by
    #   arity-0 blocks.
    def example_model_invocation(source: nil, &block)
      if block_given?
        @example_model_invocation_block = block
        @example_model_invocation = nil
      elsif @example_model_invocation_block.present?
        if @example_model_invocation_block.arity == 1
          @example_model_invocation_block.call(source)
        else
          @example_model_invocation ||= @example_model_invocation_block.call
        end
      else
        raise NotImplementedError, "#{name}#example_model_invocation is not implemented"
      end
    end

    def process_invocation(invocation)
      raise NotImplementedError, "#{name}#process_invocation is not implemented"
    end

    def invocation_partial_name
      name.gsub("Raif::ModelTools::", "").underscore
    end

    # Defines or retrieves the tool's argument schema.
    #
    # When defining:
    #   - arity-0 block with `dynamic: false`: static schema, built once at class load.
    #   - arity-0 block with `dynamic: true`: re-evaluated on every read.
    #   - arity-1 block (any `dynamic:` value): source-aware. Re-evaluated on
    #     every read and receives the caller `source` — typically the agent
    #     invoking the tool. Use this to gate fields on per-run context without
    #     reading global state. The `dynamic:` flag is implied for this form
    #     because a source-dependent schema must re-evaluate on each read.
    #
    # @param dynamic [Boolean] When true, the schema re-evaluates on each read.
    #   Automatically set to true for arity-1 blocks.
    # @param source [Object, nil] Passed into arity-1 schema blocks; ignored
    #   for static / arity-0 schemas.
    def tool_arguments_schema(dynamic: false, source: nil, &block)
      if block_given?
        # Arity-1 blocks are inherently source-dependent and must be dynamic.
        # Auto-promote so callers don't have to think about the interaction.
        dynamic = true if block.arity == 1
        json_schema_definition(:tool_arguments, dynamic: dynamic, &block)
      elsif schema_defined?(:tool_arguments)
        schema_for(:tool_arguments, source: source)
      else
        raise NotImplementedError,
          "#{name} must define tool arguments schema via tool_arguments_schema or override #{name}.tool_arguments_schema"
      end
    end

    # Backward-compatible entry point for rendering/validating a tool's schema
    # against a caller `source`. Raif's internals go through this helper (LLM
    # formatters, argument validation, argument stripping) rather than calling
    # `tool_arguments_schema(source: …)` directly so that subclasses whose
    # overrides predate the `source:` keyword keep working.
    #
    # If the tool's `tool_arguments_schema` accepts `source:` (the base
    # implementation, or an override that opted in), the helper forwards it.
    # Otherwise the helper falls back to the no-arg form — the schema simply
    # doesn't get per-call context, matching pre-source-aware behavior.
    #
    # @param source [Object, nil] The caller (typically the agent).
    # @return [Hash] The tool's JSON schema.
    def tool_arguments_schema_for_source(source)
      if method_accepts_source_kwarg?(:tool_arguments_schema)
        tool_arguments_schema(source: source)
      else
        tool_arguments_schema
      end
    end

    # Analogous backward-compatible entry point for `example_model_invocation`.
    def example_model_invocation_for_source(source)
      if method_accepts_source_kwarg?(:example_model_invocation)
        example_model_invocation(source: source)
      else
        example_model_invocation
      end
    end

    # Analogous backward-compatible entry point for `prepare_tool_arguments`.
    # Lets subclass overrides with the pre-source-aware signature
    # `def self.prepare_tool_arguments(arguments)` keep working.
    def prepare_tool_arguments_for_source(arguments, source)
      if method_accepts_source_kwarg?(:prepare_tool_arguments)
        prepare_tool_arguments(arguments, source: source)
      else
        prepare_tool_arguments(arguments)
      end
    end

    def provider_managed?
      false
    end

    def renderable?
      true
    end

    def triggers_observation_to_model?
      false
    end

    def invoke_tool(provider_tool_call_id:, tool_arguments:, source:)
      prepared_arguments = prepare_tool_arguments_for_source(tool_arguments, source)

      tool_invocation = Raif::ModelToolInvocation.new(
        provider_tool_call_id: provider_tool_call_id,
        source: source,
        tool_type: name,
        tool_arguments: prepared_arguments
      )

      ActiveRecord::Base.transaction do
        tool_invocation.save!
        process_invocation(tool_invocation)
        tool_invocation.completed!
      end

      tool_invocation
    rescue StandardError => e
      tool_invocation.failed!
      raise e
    end

    # Prepares tool arguments before validation and invocation. Override in subclasses
    # to add tool-specific argument processing (e.g. type coercion, default injection).
    # The base implementation strips keys not declared in the tool's argument schema,
    # which handles LLMs that hallucinate extra parameters.
    #
    # @param arguments [Hash] The raw tool arguments from the LLM response
    # @param source [Object, nil] The caller invoking the tool (e.g. the agent).
    #   Forwarded into the schema lookup so source-aware schemas are evaluated
    #   against the same context the model saw when selecting the tool.
    # @return [Hash] The prepared arguments ready for validation and processing
    def prepare_tool_arguments(arguments, source: nil)
      strip_unknown_tool_arguments(arguments, source: source)
    end

  private

    # True iff `method_name` (a class method on self) accepts a `source:`
    # keyword argument — either as a named kwarg or via a kwarg-rest (`**`).
    # Used to keep subclass overrides that predate the `source:` keyword
    # working.
    def method_accepts_source_kwarg?(method_name)
      method(method_name).parameters.any? do |type, name|
        (type == :key || type == :keyreq) && name == :source || type == :keyrest
      end
    end

    # Removes keys from the arguments hash that are not declared in the tool's
    # argument schema. Logs a warning when keys are stripped so hallucination
    # patterns can be monitored. Normalizes all keys to strings for consistent
    # comparison since the schema builder uses symbol keys and LLM responses
    # use string keys.
    #
    # @param arguments [Hash] The raw tool arguments
    # @param source [Object, nil] Forwarded into source-aware schema evaluation.
    # @return [Hash] The arguments with only schema-declared keys
    def strip_unknown_tool_arguments(arguments, source: nil)
      return arguments unless arguments.is_a?(Hash)

      schema = tool_arguments_schema_for_source(source)
      schema_properties = schema[:properties] || schema["properties"]
      return arguments if schema_properties.blank?

      normalized_arguments = arguments.deep_stringify_keys
      allowed_keys = schema_properties.keys.map(&:to_s)
      dropped_keys = normalized_arguments.keys - allowed_keys

      if dropped_keys.any?
        Rails.logger.warn(
          "[Raif::ModelTool] Stripped unexpected tool arguments for #{name}: #{dropped_keys.join(", ")}"
        )
      end

      normalized_arguments.slice(*allowed_keys)
    end
  end

  # Instance method to get the tool arguments schema
  # For instance-dependent schemas, builds the schema with this instance as context
  # For class-level schemas, returns the class-level schema
  def tool_arguments_schema
    schema_for_instance(:tool_arguments)
  end

end
