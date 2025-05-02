# frozen_string_literal: true

class Raif::Llms::Anthropic < Raif::Llm
  include Raif::Concerns::Llms::Anthropic::MessageFormatting

  def perform_model_completion!(model_completion)
    params = build_request_parameters(model_completion)
    response = connection.post("messages") do |req|
      req.body = params
    end

    response_json = response.body

    unless response.success?
      error_message = response_json.dig("error", "message") || "Anthropic API error: #{response.status}"
      raise Raif::Errors::Anthropic::ApiError, error_message
    end

    model_completion.raw_response = if model_completion.response_format_json?
      extract_json_response(response_json)
    else
      extract_text_response(response_json)
    end

    model_completion.response_tool_calls = extract_response_tool_calls(response_json)
    model_completion.completion_tokens = response_json&.dig("usage", "output_tokens")
    model_completion.prompt_tokens = response_json&.dig("usage", "input_tokens")
    model_completion.save!

    model_completion
  end

  def connection
    @connection ||= Faraday.new(url: "https://api.anthropic.com/v1") do |f|
      f.headers["x-api-key"] = Raif.config.anthropic_api_key
      f.headers["anthropic-version"] = "2023-06-01"
      f.request :json
      f.response :json
    end
  end

protected

  def build_request_parameters(model_completion)
    params = {
      model: model_completion.model_api_name,
      messages: model_completion.messages,
      temperature: (model_completion.temperature || default_temperature).to_f,
      max_tokens: model_completion.max_completion_tokens || default_max_completion_tokens
    }

    params[:system] = model_completion.system_prompt if model_completion.system_prompt.present?

    # Add tools to the request if needed
    tools = []

    # If we're looking for a JSON response, add a tool to the request that the model can use to provide a JSON response
    if model_completion.response_format_json? && model_completion.json_response_schema.present?
      tools << {
        name: "json_response",
        description: "Generate a structured JSON response based on the provided schema.",
        input_schema: model_completion.json_response_schema
      }
    end

    # If we support native tool use and have tools available, add them to the request
    if supports_native_tool_use? && model_completion.available_model_tools.any?
      model_completion.available_model_tools_map.each do |_tool_name, tool|
        tools << {
          name: tool.tool_name,
          description: tool.tool_description,
          input_schema: tool.tool_arguments_schema
        }
      end
    end

    params[:tools] = tools if tools.any?

    params
  end

  def extract_text_response(resp)
    resp&.dig("content")&.first&.dig("text")
  end

  def extract_json_response(resp)
    return extract_text_response(resp) if resp&.dig(:content).nil?

    # Look for tool_use blocks in the content array
    tool_name = "json_response"
    tool_response = resp&.dig("content")&.find do |content|
      content["type"] == "tool_use" && content["name"] == tool_name
    end

    if tool_response
      JSON.generate(tool_response[:input])
    else
      extract_text_response(resp)
    end
  end

  def extract_response_tool_calls(resp)
    return if resp&.dig("content").nil?

    # Find any tool_use content blocks
    tool_uses = resp&.dig("content")&.select do |content|
      content["type"] == "tool_use"
    end

    return if tool_uses.blank?

    tool_uses.map do |tool_use|
      {
        "name" => tool_use["name"],
        "arguments" => tool_use["input"]
      }
    end
  end

end
