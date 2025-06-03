# frozen_string_literal: true

class Raif::ModelTool
  include Raif::Concerns::JsonSchemaDefinition

  delegate :tool_name, :tool_description, :tool_arguments_schema, :example_model_invocation, to: :class

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

    def tool_arguments_schema(&block)
      if block_given?
        json_schema_definition(:tool_arguments, &block)
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

    def invoke_tool(tool_arguments:, source:)
      tool_invocation = Raif::ModelToolInvocation.new(
        source: source,
        tool_type: name,
        tool_arguments: tool_arguments
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
  end

end
