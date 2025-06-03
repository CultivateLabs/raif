# frozen_string_literal: true

class Raif::Llms::Anthropic < Raif::Llm
  include Raif::Concerns::Llms::Anthropic::MessageFormatting
  include Raif::Concerns::Llms::Anthropic::ToolFormatting

  def perform_model_completion!(model_completion)
    params = build_request_parameters(model_completion)
    response = connection.post("messages") do |req|
      req.body = params
    end

    response_json = response.body

    model_completion.raw_response = if model_completion.response_format_json?
      extract_json_response(response_json)
    else
      extract_text_response(response_json)
    end

    model_completion.response_id = response_json&.dig("id")
    model_completion.response_array = response_json&.dig("content")
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
      f.response :raise_error
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

    if supports_native_tool_use?
      tools = build_tools_parameter(model_completion)
      params[:tools] = tools unless tools.blank?
    end

    params
  end

  def extract_text_response(resp)
    return if resp&.dig("content").blank?

    resp.dig("content").select{|v| v["type"] == "text" }.map{|v| v["text"] }.join("\n")
  end

  def extract_json_response(resp)
    return extract_text_response(resp) if resp&.dig("content").nil?

    # Look for tool_use blocks in the content array
    tool_response = resp&.dig("content")&.find do |content|
      content["type"] == "tool_use" && content["name"] == "json_response"
    end

    if tool_response
      JSON.generate(tool_response["input"])
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
