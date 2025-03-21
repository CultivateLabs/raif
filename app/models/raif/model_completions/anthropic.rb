# frozen_string_literal: true

class Raif::ModelCompletions::Anthropic < Raif::ModelCompletions::AnthropicBase
protected

  def build_api_parameters
    params = {
      model: model_api_name,
      messages: messages,
      temperature: temperature.to_f,
      max_tokens: max_completion_tokens
    }

    params[:system] = system_prompt if system_prompt

    # Handle JSON response formats
    if response_format_json?
      # Create a tool for structured JSON output
      json_tool = format_json_tool(create_json_tool)
      params[:tools] = [json_tool]
      # params[:tool_choice] = { type: "tool", name: json_tool[:name] }
    end

    params
  end

  def make_api_call(params)
    ::Anthropic.messages.create(**params)
  end

  def extract_token_usage(resp)
    self.completion_tokens = resp.body&.dig(:usage, :output_tokens)
    self.prompt_tokens = resp.body&.dig(:usage, :input_tokens)
    self.total_tokens = completion_tokens.present? && prompt_tokens.present? ? completion_tokens + prompt_tokens : nil
  end

  def extract_text_response(resp)
    resp.body&.dig(:content)&.first&.dig(:text)
  end

  def extract_json_response(resp)
    return extract_text_response(resp) if resp.body&.dig(:content).nil?

    # Look for tool_use blocks in the content array
    tool_name = "json_response"
    tool_response = resp.body&.dig(:content)&.find do |content|
      content[:type] == "tool_use" && content[:name] == tool_name
    end

    if tool_response
      JSON.generate(tool_response[:input])
    else
      extract_text_response(resp)
    end
  end

private

  def format_json_tool(tool_base)
    {
      name: tool_base[:name],
      description: tool_base[:description],
      input_schema: tool_base[:schema]
    }
  end
end
