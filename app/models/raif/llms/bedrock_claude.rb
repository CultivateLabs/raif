# frozen_string_literal: true

class Raif::Llms::BedrockClaude < Raif::Llm
  include Raif::Concerns::Llms::BedrockClaude::MessageFormatting

  def perform_model_completion!(model_completion)
    if Raif.config.aws_bedrock_model_name_prefix.present?
      model_completion.model_api_name = "#{Raif.config.aws_bedrock_model_name_prefix}.#{model_completion.model_api_name}"
    end

    params = build_request_parameters(model_completion)
    resp = bedrock_client.converse(params)

    model_completion.raw_response = if model_completion.response_format_json?
      extract_json_response(resp)
    else
      extract_text_response(resp)
    end

    model_completion.completion_tokens = resp.usage.output_tokens
    model_completion.prompt_tokens = resp.usage.input_tokens
    model_completion.total_tokens = resp.usage.total_tokens
    model_completion.save!

    model_completion
  end

protected

  def bedrock_client
    @bedrock_client ||= Aws::BedrockRuntime::Client.new(region: Raif.config.aws_bedrock_region)
  end

  def build_request_parameters(model_completion)
    # The AWS Bedrock SDK requires symbols for keys
    messages_param = model_completion.messages.map(&:deep_symbolize_keys)
    replace_tmp_base64_data_with_bytes(messages_param)

    params = {
      model_id: model_completion.model_api_name,
      inference_config: { max_tokens: model_completion.max_completion_tokens || 8192 },
      messages: messages_param
    }

    params[:system] = [{ text: model_completion.system_prompt }] if model_completion.system_prompt.present?

    tool_config = build_tool_parameters(model_completion)
    params[:tool_config] = tool_config if tool_config.present?

    params
  end

  def replace_tmp_base64_data_with_bytes(messages)
    # The AWS Bedrock SDK requires data sent as bytes (and doesn't support base64 like everyone else)
    # The ModelCompletion stores the messages as JSON though, so it can't be raw bytes.
    # We store the image data as base64, so we need to convert that to bytes before sending to AWS.
    messages.each do |message|
      message[:content].each do |content|
        next unless content[:image] || content[:document]

        type_key = content[:image] ? :image : :document
        base64_data = content[type_key][:source].delete(:tmp_base64_data)
        content[type_key][:source][:bytes] = Base64.strict_decode64(base64_data)
      end
    end
  end

  def build_tool_parameters(model_completion)
    tools = []

    # If we're looking for a JSON response, add a tool to the request that the model can use to provide a JSON response
    if model_completion.response_format_json? && model_completion.json_response_schema.present?
      tools << {
        name: "json_response",
        description: "Generate a structured JSON response based on the provided schema.",
        input_schema: { json: model_completion.json_response_schema }
      }
    end

    # If we support native tool use and have tools available, add them to the request
    if supports_native_tool_use? && model_completion.available_model_tools.any?
      model_completion.available_model_tools_map.each do |_tool_name, tool|
        tools << {
          name: tool.tool_name,
          description: tool.tool_description,
          input_schema: { json: tool.tool_arguments_schema }
        }
      end
    end

    return if tools.blank?

    {
      tools: tools.map{|tool| { tool_spec: tool } }
    }
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

  def extract_response_tool_calls(resp)
    # Get the message from the response object
    message = resp.output.message
    return if message.content.nil?

    # Find any tool_use blocks in the content array
    tool_uses = message.content.select do |content|
      content.respond_to?(:tool_use) && content.tool_use.present?
    end

    return if tool_uses.blank?

    tool_uses.map do |content|
      {
        "name" => content.tool_use.name,
        "arguments" => content.tool_use.input
      }
    end
  end

end
