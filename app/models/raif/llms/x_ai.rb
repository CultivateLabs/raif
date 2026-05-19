# frozen_string_literal: true

class Raif::Llms::XAi < Raif::Llm
  include Raif::Concerns::Llms::OpenAiCompletions::MessageFormatting
  include Raif::Concerns::Llms::OpenAiCompletions::ToolFormatting
  include Raif::Concerns::Llms::OpenAiCompletions::ResponseToolCalls
  include Raif::Concerns::Llms::OpenAi::JsonSchemaValidation
  include Raif::Concerns::Llms::XAi::BatchInference

  def perform_model_completion!(model_completion, &block)
    model_completion.temperature ||= default_temperature
    parameters = build_request_parameters(model_completion)
    response = connection.post("chat/completions") do |req|
      req.body = parameters
      req.options.on_data = streaming_chunk_handler(model_completion, &block) if model_completion.stream_response?
    end

    unless model_completion.stream_response?
      update_model_completion(model_completion, response.body)
    end

    model_completion
  end

private

  def connection
    @connection ||= Faraday.new(url: "https://api.x.ai/v1", request: Raif.default_request_options) do |f|
      f.headers["Authorization"] = "Bearer #{Raif.config.x_ai_api_key}"
      f.request :json
      f.response :json
      f.response :raise_error
    end
  end

  def streaming_response_type
    Raif::StreamingResponses::OpenAiCompletions
  end

  def update_model_completion(model_completion, response_json)
    return if response_json.nil?

    model_completion.update!(
      response_id: response_json["id"],
      response_tool_calls: extract_response_tool_calls(response_json),
      raw_response: response_json.dig("choices", 0, "message", "content"),
      response_array: response_json["choices"],
      completion_tokens: response_json.dig("usage", "completion_tokens"),
      prompt_tokens: response_json.dig("usage", "prompt_tokens"),
      total_tokens: response_json.dig("usage", "total_tokens"),
      cache_read_input_tokens: response_json.dig("usage", "prompt_tokens_details", "cached_tokens")
    )
  end

  def build_request_parameters(model_completion)
    messages = model_completion.messages
    messages_with_system = if model_completion.system_prompt.present?
      [{ "role" => "system", "content" => model_completion.system_prompt }] + messages
    else
      messages
    end

    params = {
      model: model_completion.model_api_name,
      messages: messages_with_system,
      temperature: model_completion.temperature.to_f,
      max_tokens: model_completion.max_completion_tokens || default_max_completion_tokens,
    }

    if supports_native_tool_use?
      tools = build_tools_parameter(model_completion)
      params[:tools] = tools unless tools.blank?

      if model_completion.tool_choice == "required"
        params[:tool_choice] = build_required_tool_choice
      elsif model_completion.tool_choice.present?
        tool_klass = model_completion.tool_choice.constantize
        params[:tool_choice] = build_forced_tool_choice(tool_klass.tool_name)
      end
    end

    if model_completion.stream_response?
      params[:stream] = true
      params[:stream_options] = { include_usage: true }
    end

    if model_completion.json_response_schema.present?
      # xAI documents native structured outputs for the Grok 4 family on
      # /v1/chat/completions. Use response_format: json_schema so the schema
      # is enforced provider-side rather than via a synthetic function-tool.
      # https://docs.x.ai/developers/model-capabilities/text/structured-outputs
      validate_json_schema!(model_completion.json_response_schema)
      params[:response_format] = {
        type: "json_schema",
        json_schema: {
          name: "json_response_schema",
          strict: true,
          schema: model_completion.json_response_schema
        }
      }
      model_completion.response_format_parameter = "json_schema"
    elsif model_completion.response_format_json?
      params[:response_format] = { type: "json_object" }
      model_completion.response_format_parameter = "json_object"
    end

    params
  end
end
