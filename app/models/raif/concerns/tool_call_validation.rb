# frozen_string_literal: true

# Shared validation logic for developer-managed tool calls returned by an LLM.
# Produces a structured result so callers (agents, conversations) can apply
# their own retry/error semantics.
#
# Validation checks, in order:
# 1. Tool exists in the provided tool map.
# 2. `prepare_tool_arguments` on the tool class yields a Hash.
# 3. The prepared Hash satisfies the tool's `tool_arguments_schema`.
module Raif::Concerns::ToolCallValidation
  extend ActiveSupport::Concern

  ValidationResult = Struct.new(:status, :tool_name, :raw_arguments, :prepared_arguments, :tool_klass, :errors, keyword_init: true) do
    def ok?
      status == :ok
    end
  end

  # @param tool_call [Hash] A tool call Hash as returned by `ModelCompletion#response_tool_calls`.
  #   Expected shape: { "name" => String, "arguments" => anything, "provider_tool_call_id" => String? }
  # @param available_model_tools_map [Hash{String => Class}] Map of tool name to tool class.
  # @return [ValidationResult]
  def validate_tool_call(tool_call, available_model_tools_map)
    tool_name = tool_call["name"]
    raw_arguments = tool_call["arguments"]
    tool_klass = available_model_tools_map[tool_name]

    if tool_klass.nil?
      return ValidationResult.new(
        status: :unknown_tool,
        tool_name: tool_name,
        raw_arguments: raw_arguments,
        prepared_arguments: nil,
        tool_klass: nil,
        errors: nil
      )
    end

    # Tools may override `prepare_tool_arguments`; the base implementation is
    # safe, but subclass overrides can raise on unexpected input shapes. Rescue
    # so the retry loop sees a structured :preparation_error rather than
    # exploding out of validation.
    begin
      prepared = tool_klass.prepare_tool_arguments(raw_arguments)
    rescue StandardError => e
      return ValidationResult.new(
        status: :preparation_error,
        tool_name: tool_name,
        raw_arguments: raw_arguments,
        prepared_arguments: nil,
        tool_klass: tool_klass,
        errors: ["#{e.class.name}: #{e.message}"]
      )
    end

    unless prepared.is_a?(Hash)
      return ValidationResult.new(
        status: :non_hash_arguments,
        tool_name: tool_name,
        raw_arguments: raw_arguments,
        prepared_arguments: prepared,
        tool_klass: tool_klass,
        errors: nil
      )
    end

    validation_errors = JSON::Validator.fully_validate(tool_klass.tool_arguments_schema, prepared)
    if validation_errors.any?
      return ValidationResult.new(
        status: :schema_mismatch,
        tool_name: tool_name,
        raw_arguments: raw_arguments,
        prepared_arguments: prepared,
        tool_klass: tool_klass,
        errors: validation_errors
      )
    end

    ValidationResult.new(
      status: :ok,
      tool_name: tool_name,
      raw_arguments: raw_arguments,
      prepared_arguments: prepared,
      tool_klass: tool_klass,
      errors: nil
    )
  end
end
