# frozen_string_literal: true

# Validates a native structured output reply against the caller's original schema.
# The schema sent to the provider has been through a strict transformer that drops
# constraints such as minimum and maximum, so the provider's constrained decoding
# does not enforce them. The including adapter supplies use_native_structured_outputs?
# and refusal_finish_reasons.
module Raif::Concerns::Llms::NativeJsonResponseValidation
  extend ActiveSupport::Concern

private

  def validate_native_json_response!(model_completion)
    return unless use_native_structured_outputs?(model_completion)
    return if model_completion.response_finish_reason.blank?
    return if refusal_finish_reasons.include?(model_completion.response_finish_reason)
    return if model_completion.raw_response.blank?
    return if model_completion.response_tool_calls.present?

    validation_errors = JSON::Validator.fully_validate(
      model_completion.json_response_schema,
      model_completion.parsed_response(force_reparse: true)
    )
    return if validation_errors.empty?

    raise_truncated_json_response!(model_completion)
    raise Raif::Errors::InvalidJsonResponseError,
      "Native JSON response did not satisfy the original schema: #{validation_errors.join("; ")}"
  rescue JSON::ParserError => e
    raise_truncated_json_response!(model_completion)
    raise Raif::Errors::InvalidJsonResponseError,
      "Native JSON response could not be parsed: #{e.message}"
  end

  # JSON cut off at the output limit is invalid because it is incomplete, not because
  # the model ignored the schema, so report it as a truncation.
  def raise_truncated_json_response!(model_completion)
    return unless model_completion.truncated?

    raise Raif::Errors::TruncatedResponseError,
      "Native JSON response was cut off at the output limit (finish reason: #{model_completion.response_finish_reason})"
  end
end
