# frozen_string_literal: true

class Raif::Llms::OpenRouter < Raif::Llm
  include Raif::Concerns::Llms::OpenAiCompletions::MessageFormatting
  include Raif::Concerns::Llms::OpenAiCompletions::ToolFormatting
  include Raif::Concerns::Llms::OpenAi::JsonSchemaValidation

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
    @connection ||= Faraday.new(url: "https://openrouter.ai/api/v1") do |f|
      f.headers["Authorization"] = "Bearer #{Raif.config.open_router_api_key}"
      f.headers["HTTP-Referer"] = Raif.config.open_router_site_url if Raif.config.open_router_site_url.present?
      f.headers["X-Title"] = Raif.config.open_router_app_name if Raif.config.open_router_app_name.present?
      f.request :json
      f.response :json
      f.response :raise_error
    end
  end

  def streaming_response_type
    Raif::StreamingResponses::OpenAiCompletions
  end

  def update_model_completion(model_completion, response_json)
    raw_response = if model_completion.response_format_json?
      extract_json_response(response_json)
    else
      extract_text_response(response_json)
    end

    model_completion.update!(
      response_id: response_json["id"],
      response_tool_calls: extract_response_tool_calls(response_json),
      raw_response: raw_response,
      response_array: response_json["choices"],
      completion_tokens: response_json.dig("usage", "completion_tokens"),
      prompt_tokens: response_json.dig("usage", "prompt_tokens"),
      total_tokens: response_json.dig("usage", "total_tokens")
    )
  end

  def build_request_parameters(model_completion)
    params = {
      model: model_completion.model_api_name,
      messages: model_completion.messages,
      temperature: model_completion.temperature.to_f,
      max_tokens: model_completion.max_completion_tokens || default_max_completion_tokens,
    }

    # Add system message to the messages array if present
    if model_completion.system_prompt.present?
      params[:messages].unshift({ "role" => "system", "content" => model_completion.system_prompt })
    end

    if supports_native_tool_use?
      tools = build_tools_parameter(model_completion)

      if model_completion.json_response_schema.present?
        validate_json_schema!(model_completion.json_response_schema)

        tools << {
          type: "function",
          function: {
            name: "json_response",
            description: "Generate a structured JSON response based on the provided schema.",
            parameters: model_completion.json_response_schema
          }
        }
      end

      params[:tools] = tools unless tools.blank?
    end

    if model_completion.stream_response?
      # Ask for usage stats in the last chunk
      params[:stream] = true
      params[:stream_options] = { include_usage: true }
    end

    if model_completion.response_format_json? && params[:tools].blank?
      params[:response_format] = { type: "json_object" }
      model_completion.response_format_parameter = "json_object"
    end

    params
  end

  def extract_text_response(resp)
    resp&.dig("choices", 0, "message", "content")
  end

  def extract_json_response(resp)
    tool_calls = resp.dig("choices", 0, "message", "tool_calls")
    return extract_text_response(resp) if tool_calls.blank?

    tool_response = tool_calls.find do |tool_call|
      tool_call["function"]["name"] == "json_response"
    end

    if tool_response&.dig("function", "arguments")
      tool_response["function"]["arguments"]
    else
      extract_text_response(resp)
    end
  end

  def extract_response_tool_calls(resp)
    tool_calls = resp.dig("choices", 0, "message", "tool_calls")
    return if tool_calls.blank?

    tool_calls.map do |tool_call|
      {
        "name" => tool_call["function"]["name"],
        "arguments" => JSON.parse(tool_call["function"]["arguments"])
      }
    end
  end
end
