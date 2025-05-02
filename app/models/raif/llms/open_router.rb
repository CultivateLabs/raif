# frozen_string_literal: true

class Raif::Llms::OpenRouter < Raif::Llm
  include Raif::Concerns::Llms::OpenAi::MessageFormatting

  def perform_model_completion!(model_completion)
    model_completion.temperature ||= default_temperature
    parameters = build_request_parameters(model_completion)
    response = connection.post("chat/completions") do |req|
      req.body = parameters
    end

    response_json = response.body

    # Handle API errors
    unless response.success?
      error_message = response_json.dig("error", "message") || "OpenRouter API error: #{response.status}"
      raise Raif::Errors::OpenRouter::ApiError, error_message
    end

    model_completion.update!(
      response_tool_calls: extract_response_tool_calls(response_json),
      raw_response: response_json.dig("choices", 0, "message", "content"),
      completion_tokens: response_json.dig("usage", "completion_tokens"),
      prompt_tokens: response_json.dig("usage", "prompt_tokens"),
      total_tokens: response_json.dig("usage", "total_tokens")
    )

    model_completion
  end

  def connection
    @connection ||= Faraday.new(url: "https://openrouter.ai/api/v1") do |f|
      f.headers["Authorization"] = "Bearer #{Raif.config.open_router_api_key}"
      f.headers["HTTP-Referer"] = Raif.config.open_router_site_url if Raif.config.open_router_site_url.present?
      f.headers["X-Title"] = Raif.config.open_router_app_name if Raif.config.open_router_app_name.present?
      f.request :json
      f.response :json
    end
  end

protected

  def build_request_parameters(model_completion)
    params = {
      model: model_completion.model_api_name,
      messages: model_completion.messages,
      temperature: model_completion.temperature.to_f,
      max_tokens: model_completion.max_completion_tokens || default_max_completion_tokens,
      stream: false
    }

    # Add system message to the messages array if present
    if model_completion.system_prompt.present?
      params[:messages].unshift({ "role" => "system", "content" => model_completion.system_prompt })
    end

    if model_completion.available_model_tools.any?
      tools = []

      model_completion.available_model_tools_map.each do |_tool_name, tool|
        tools << {
          type: "function",
          function: {
            name: tool.tool_name,
            description: tool.tool_description,
            parameters: tool.tool_arguments_schema
          }
        }
      end

      params[:tools] = tools
    end

    params
  end

  def extract_response_tool_calls(response_json)
    tool_calls = response_json.dig("choices", 0, "message", "tool_calls")
    return [] unless tool_calls.is_a?(Array)

    tool_calls.map do |tool_call|
      next unless tool_call["type"] == "function"

      function = tool_call["function"]
      next unless function.is_a?(Hash)

      {
        "id" => tool_call["id"],
        "type" => "function",
        "function" => {
          "name" => function["name"],
          "arguments" => function["arguments"]
        }
      }
    end.compact
  end
end
