# frozen_string_literal: true

class Raif::Llms::BedrockMantle < Raif::Llm
  include Raif::Concerns::Llms::OpenAiCompletions::MessageFormatting
  include Raif::Concerns::Llms::OpenAiCompletions::ToolFormatting
  include Raif::Concerns::Llms::OpenAiCompletions::ResponseToolCalls
  include Raif::Concerns::Llms::OpenAi::JsonSchemaValidation

  def perform_model_completion!(model_completion, &block)
    parameters = build_request_parameters(model_completion)
    response = connection.post("chat/completions") do |req|
      req.body = JSON.generate(parameters)
      req.headers.merge!(request_signer.sign_request(
        http_method: "POST",
        url: connection.build_url(req.path, req.params),
        headers: { "Content-Type" => "application/json" },
        body: req.body
      ).headers)
      req.options.on_data = streaming_chunk_handler(model_completion, &block) if model_completion.stream_response?
    end

    unless model_completion.stream_response?
      update_model_completion(model_completion, response.body)
    end

    model_completion
  end

private

  def connection
    @connection ||= Faraday.new(url: Raif.config.bedrock_mantle_base_url, request: Raif.default_request_options) do |f|
      f.headers["Content-Type"] = "application/json"
      f.response :json
      f.response :raise_error
    end
  end

  def request_signer
    @request_signer ||= begin
      config = Aws::BedrockRuntime::Client.new(region: Raif.config.aws_bedrock_region, max_attempts: 1).config
      raise Aws::Errors::MissingCredentialsError unless config.credentials

      # Retain the provider so temporary role/SSO credentials refresh when signing each request.
      Aws::Sigv4::Signer.new(service: "bedrock-mantle", region: config.region, credentials_provider: config.credentials)
    end
  end

  def streaming_response_type
    Raif::StreamingResponses::OpenAiCompletions
  end

  def update_model_completion(model_completion, response_json)
    return if response_json.nil?

    model_completion.update!(
      response_id: response_json["id"],
      response_finish_reason: response_json.dig("choices", 0, "finish_reason"),
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
      temperature: model_completion.temperature.to_f
    }

    max_tokens = model_completion.max_completion_tokens || default_max_completion_tokens
    params[:max_tokens] = max_tokens if max_tokens.present?

    if supports_native_tool_use?
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
    end

    if model_completion.stream_response?
      params[:stream] = true
      params[:stream_options] = { include_usage: true }
    end

    if model_completion.json_response_schema.present?
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
