# frozen_string_literal: true

class Raif::Llms::XAi < Raif::Llm
  include Raif::Concerns::Llms::OpenAiCompletions::Protocol
  include Raif::Concerns::Llms::XAi::BatchInference

  def perform_model_completion!(model_completion, &block)
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
    @connection ||= Faraday.new(url: Raif.config.x_ai_base_url, request: Raif.default_request_options) do |f|
      f.headers["Authorization"] = "Bearer #{Raif.config.x_ai_api_key}"
      f.request :json
      f.response :json
      f.response :raise_error
    end
  end

  def update_model_completion(model_completion, response_json)
    return if response_json.nil?

    model_completion.update!(
      chat_completions_response_attributes(response_json).merge(completion_tokens: derive_completion_tokens(response_json))
    )
  end

  # xAI reports usage.completion_tokens as visible-output-only and exposes
  # reasoning tokens separately in usage.completion_tokens_details.reasoning_tokens
  # (total_tokens = prompt + completion + reasoning). Roll them together so
  # Raif::ModelCompletion#calculate_costs charges reasoning tokens at the
  # output rate, matching what xAI actually bills.
  def derive_completion_tokens(response_json)
    visible = response_json.dig("usage", "completion_tokens")
    return if visible.nil?

    reasoning = response_json.dig("usage", "completion_tokens_details", "reasoning_tokens").to_i
    visible + reasoning
  end

  # The system prompt is sent unchanged. OpenAiBase appends "Return your response as
  # JSON." because OpenAI's json_object mode requires the word JSON in the prompt;
  # xAI does not document that requirement.
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
