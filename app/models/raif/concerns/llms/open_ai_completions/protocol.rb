# frozen_string_literal: true

# The parts of the OpenAI Chat Completions protocol that every adapter speaking it
# must build identically: tool parameters, streaming flags, response_format, and the
# mapping from a response body onto a Raif::ModelCompletion. Adapters compose these
# from their own build_request_parameters, which keeps the provider-specific base
# parameters (model name, system prompt shaping, temperature, max_tokens) visible in
# the adapter while the shared pieces cannot drift between OpenAiCompletions, XAi,
# and BedrockMantle.
module Raif::Concerns::Llms::OpenAiCompletions::Protocol
  extend ActiveSupport::Concern

  include Raif::Concerns::Llms::OpenAiCompletions::MessageFormatting
  include Raif::Concerns::Llms::OpenAiCompletions::ToolFormatting
  include Raif::Concerns::Llms::OpenAiCompletions::ResponseToolCalls
  include Raif::Concerns::Llms::OpenAi::JsonSchemaValidation

private

  def streaming_response_type
    Raif::StreamingResponses::OpenAiCompletions
  end

  def chat_completions_messages(model_completion, system_prompt: model_completion.system_prompt)
    return model_completion.messages if system_prompt.blank?

    [{ "role" => "system", "content" => system_prompt }] + model_completion.messages
  end

  def apply_chat_completions_tool_parameters!(params, model_completion)
    return params unless supports_native_tool_use?

    tools = build_tools_parameter(model_completion)
    params[:tools] = tools unless tools.blank?

    if model_completion.tool_choice == "required"
      params[:tool_choice] = build_required_tool_choice
      params[:parallel_tool_calls] = (model_completion.allow_parallel_tool_calls == true) unless tools.blank?
    elsif model_completion.tool_choice.present?
      tool_klass = model_completion.tool_choice.constantize
      params[:tool_choice] = build_forced_tool_choice(tool_klass.tool_name)
      params[:parallel_tool_calls] = false unless tools.blank?
    end
    # With no tool_choice (conversations, tasks, normal agent iterations) the parameter
    # is intentionally omitted so the request inherits the provider default (parallel
    # allowed), which the conversation and agent paths both handle.

    params
  end

  def apply_chat_completions_streaming_parameters!(params, model_completion)
    return params unless model_completion.stream_response?

    params[:stream] = true
    # Ask for usage stats in the last chunk
    params[:stream_options] = { include_usage: true }
    params
  end

  def apply_chat_completions_response_format!(params, model_completion)
    response_format = determine_response_format(model_completion)
    return params unless response_format

    params[:response_format] = response_format
    model_completion.response_format_parameter = response_format[:type]
    params
  end

  # Only JSON completions carry a response_format: a source may define a
  # json_response_schema while asking for text, so response_format_json? is checked
  # first. The schema is sent natively only when the model supports structured
  # outputs; otherwise the request falls back to plain JSON mode.
  def determine_response_format(model_completion)
    return unless model_completion.response_format_json?

    if model_completion.json_response_schema.present? && supports_structured_outputs?
      validate_json_schema!(model_completion.json_response_schema)

      {
        type: "json_schema",
        json_schema: {
          name: "json_response_schema",
          strict: true,
          schema: model_completion.json_response_schema
        }
      }
    else
      { type: "json_object" }
    end
  end

  def chat_completions_response_attributes(response_json)
    {
      response_id: response_json["id"],
      response_finish_reason: response_json.dig("choices", 0, "finish_reason"),
      response_tool_calls: extract_response_tool_calls(response_json),
      raw_response: response_json.dig("choices", 0, "message", "content"),
      response_array: response_json["choices"],
      completion_tokens: response_json.dig("usage", "completion_tokens"),
      prompt_tokens: response_json.dig("usage", "prompt_tokens"),
      total_tokens: response_json.dig("usage", "total_tokens"),
      cache_read_input_tokens: response_json.dig("usage", "prompt_tokens_details", "cached_tokens")
    }
  end

  def update_model_completion(model_completion, response_json)
    return if response_json.nil?

    model_completion.update!(chat_completions_response_attributes(response_json))
  end
end
