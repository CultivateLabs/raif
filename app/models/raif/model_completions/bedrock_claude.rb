# frozen_string_literal: true

class Raif::ModelCompletions::BedrockClaude < Raif::ModelCompletions::AnthropicBase
  def formatted_messages
    messages.map(&:symbolize_keys).map do |message|
      {
        role: message[:role],
        content: [{ text: message[:content] }]
      }
    end
  end

protected

  def build_api_parameters
    params = {
      model_id: model_api_name,
      inference_config: { max_tokens: max_completion_tokens || 8192 },
      messages: formatted_messages
    }

    params[:system] = [{ text: system_prompt }] if system_prompt.present?

    # Handle JSON response formats
    if response_format_json?
      json_tool = format_json_tool(create_json_tool)
      params[:tool_config] = {
        tools: [{ tool_spec: json_tool }],
        tool_choice: { tool: { name: json_tool[:name] } }
      }
    end

    params
  end

  def make_api_call(params)
    client = Aws::BedrockRuntime::Client.new(region: Raif.config.aws_bedrock_region)
    client.converse(params)
  end

  def extract_token_usage(resp)
    self.completion_tokens = resp.usage.output_tokens
    self.prompt_tokens = resp.usage.input_tokens
    self.total_tokens = resp.usage.total_tokens
  end

  def extract_text_response(resp)
    # Get the message from the response object
    message = resp.output.message

    # Find the first text content block
    text_block = message.content&.find do |content|
      content.respond_to?(:text) && content.text.present?
    end

    text_block&.text
  end

  def extract_json_response(resp)
    # Get the message from the response object
    message = resp.output.message

    return extract_text_response(resp) if message.content.nil?

    # Look for tool_use blocks in the content array
    tool_response = message.content.find do |content|
      content.respond_to?(:tool_use) && content.tool_use.present? && content.tool_use.name == "json_response"
    end

    if tool_response&.tool_use
      JSON.generate(tool_response.tool_use.input)
    else
      extract_text_response(resp)
    end
  end

private

  def format_json_tool(tool_base)
    {
      name: tool_base[:name],
      description: tool_base[:description],
      input_schema: { json: tool_base[:schema] }
    }
  end
end
