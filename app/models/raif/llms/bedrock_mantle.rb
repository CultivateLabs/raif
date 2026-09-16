# frozen_string_literal: true

# Bedrock Mantle is AWS's OpenAI-compatible Chat Completions endpoint for Bedrock
# models. It shares the Chat Completions protocol with OpenAiCompletions and XAi but
# authenticates with SigV4 from the AWS SDK credential chain instead of an API key.
class Raif::Llms::BedrockMantle < Raif::Llm
  include Raif::Concerns::Llms::OpenAiCompletions::Protocol

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
      provider = aws_credentials_provider
      raise Aws::Errors::MissingCredentialsError unless provider

      # Pass the provider, not a credentials snapshot, so temporary role/SSO credentials
      # refresh when each request is signed.
      Aws::Sigv4::Signer.new(service: "bedrock-mantle", region: Raif.config.aws_bedrock_region, credentials_provider: provider)
    end
  end

  # Resolved through a throwaway BedrockRuntime client so Mantle honours exactly the
  # credential resolution the Converse adapter uses: environment, shared config and
  # profiles, SSO, assumed roles, and container/instance metadata. A bare
  # Aws::CredentialProviderChain would skip the client's own configuration plugins.
  def aws_credentials_provider
    Aws::BedrockRuntime::Client.new(region: Raif.config.aws_bedrock_region, max_attempts: 1).config.credentials
  end

  # Matches XAi: the system prompt is sent unchanged. OpenAiBase appends "Return your
  # response as JSON." because OpenAI's json_object mode requires the word JSON in the
  # prompt; the Grok models served here are xAI's, which does not document that.
  def build_request_parameters(model_completion)
    params = {
      model: model_completion.model_api_name,
      messages: chat_completions_messages(model_completion)
    }
    params[:temperature] = model_completion.temperature.to_f if supports_temperature?

    max_tokens = model_completion.max_completion_tokens || default_max_completion_tokens
    params[:max_tokens] = max_tokens if max_tokens.present?

    apply_chat_completions_tool_parameters!(params, model_completion)
    apply_chat_completions_streaming_parameters!(params, model_completion)
    apply_chat_completions_response_format!(params, model_completion)
  end
end
