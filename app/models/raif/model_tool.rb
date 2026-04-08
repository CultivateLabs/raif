# frozen_string_literal: true

class Raif::ModelTool
  include Raif::Concerns::JsonSchemaDefinition

  delegate :tool_name, :tool_description, :example_model_invocation, to: :class

  class << self
    # The description of the tool that will be provided to the model
    # when giving it a list of available tools.
    def description_for_llm
      <<~DESCRIPTION
        Name: #{tool_name}
        Description: #{tool_description}
        Arguments Schema:
        #{JSON.pretty_generate(tool_arguments_schema)}
        Example Usage:
        #{JSON.pretty_generate(example_model_invocation)}
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

    def example_model_invocation(&block)
      if block_given?
        @example_model_invocation = block.call
      elsif @example_model_invocation.present?
        @example_model_invocation
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

    def tool_arguments_schema(dynamic: false, &block)
      if block_given?
        json_schema_definition(:tool_arguments, dynamic: dynamic, &block)
      elsif schema_defined?(:tool_arguments)
        schema_for(:tool_arguments)
      else
        raise NotImplementedError,
          "#{name} must define tool arguments schema via tool_arguments_schema or override #{name}.tool_arguments_schema"
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
      prepared_arguments = prepare_tool_arguments(tool_arguments)

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
    # @return [Hash] The prepared arguments ready for validation and processing
    def prepare_tool_arguments(arguments)
      strip_unknown_tool_arguments(arguments)
    end

  private

    # Removes keys from the arguments hash that are not declared in the tool's
    # argument schema. Logs a warning when keys are stripped so hallucination
    # patterns can be monitored. Normalizes all keys to strings for consistent
    # comparison since the schema builder uses symbol keys and LLM responses
    # use string keys.
    #
    # @param arguments [Hash] The raw tool arguments
    # @return [Hash] The arguments with only schema-declared keys
    def strip_unknown_tool_arguments(arguments)
      return arguments unless arguments.is_a?(Hash)

      schema_properties = tool_arguments_schema[:properties] || tool_arguments_schema["properties"]
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
