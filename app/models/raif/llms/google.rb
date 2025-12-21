# frozen_string_literal: true

class Raif::Llms::Google < Raif::Llm
  include Raif::Concerns::Llms::Google::MessageFormatting
  include Raif::Concerns::Llms::Google::ToolFormatting
  include Raif::Concerns::Llms::Google::ResponseToolCalls

  def perform_model_completion!(model_completion, &block)
    params = build_request_parameters(model_completion)
    endpoint = build_endpoint(model_completion)

    response = connection.post(endpoint) do |req|
      req.body = params
      req.options.on_data = streaming_chunk_handler(model_completion, &block) if model_completion.stream_response?
    end

    unless model_completion.stream_response?
      update_model_completion(model_completion, response.body)
    end

    model_completion
  end

private

  def connection
    @connection ||= Faraday.new(url: "https://generativelanguage.googleapis.com/v1beta") do |f|
      f.headers["x-goog-api-key"] = Raif.config.google_api_key
      f.request :json
      f.response :json
      f.response :raise_error
    end
  end

  def build_endpoint(model_completion)
    if model_completion.stream_response?
      "models/#{model_completion.model_api_name}:streamGenerateContent?alt=sse"
    else
      "models/#{model_completion.model_api_name}:generateContent"
    end
  end

  def streaming_response_type
    Raif::StreamingResponses::Google
  end

  def update_model_completion(model_completion, response_json)
    model_completion.raw_response = if model_completion.response_format_json?
      extract_json_response(response_json)
    else
      extract_text_response(response_json)
    end

    model_completion.response_array = response_json&.dig("candidates", 0, "content", "parts")
    model_completion.response_tool_calls = extract_response_tool_calls(response_json)
    model_completion.citations = extract_citations(response_json)
    model_completion.completion_tokens = response_json&.dig("usageMetadata", "candidatesTokenCount")
    model_completion.prompt_tokens = response_json&.dig("usageMetadata", "promptTokenCount")
    model_completion.total_tokens = response_json&.dig("usageMetadata", "totalTokenCount") ||
      (model_completion.completion_tokens.to_i + model_completion.prompt_tokens.to_i)
    model_completion.save!
  end

  def build_request_parameters(model_completion)
    params = {
      contents: model_completion.messages
    }

    if model_completion.system_prompt.present?
      params[:system_instruction] = { parts: [{ text: model_completion.system_prompt }] }
    end

    params[:generationConfig] = build_generation_config(model_completion)

    if supports_native_tool_use?
      tools = build_tools_parameter(model_completion)
      params[:tools] = tools unless tools.blank?

      if model_completion.tool_choice.present?
        tool_klass = model_completion.tool_choice.constantize
        params[:toolConfig] = { functionCallingConfig: build_forced_tool_choice(tool_klass.tool_name) }
      end
    end

    params
  end

  def build_generation_config(model_completion)
    config = {}

    temperature = model_completion.temperature || default_temperature
    config[:temperature] = temperature.to_f if temperature.present?

    max_tokens = model_completion.max_completion_tokens || default_max_completion_tokens
    config[:maxOutputTokens] = max_tokens if max_tokens.present?

    # Use native JSON schema support for structured output
    if model_completion.response_format_json? && model_completion.json_response_schema.present?
      config[:responseMimeType] = "application/json"
      config[:responseSchema] = sanitize_schema_for_google(model_completion.json_response_schema)
    end

    config
  end

  def extract_text_response(resp)
    parts = resp&.dig("candidates", 0, "content", "parts")
    return if parts.blank?

    parts.select { |p| p.key?("text") }.map { |p| p["text"] }.join
  end

  def extract_json_response(resp)
    # Google AI supports native JSON schema output, so the response should be in the text field
    extract_text_response(resp)
  end

  def extract_citations(resp)
    # Google AI returns grounding metadata for search results
    grounding_metadata = resp&.dig("candidates", 0, "groundingMetadata")
    return [] if grounding_metadata.blank?

    citations = []

    # Extract from grounding chunks
    grounding_chunks = grounding_metadata["groundingChunks"] || []
    grounding_chunks.each do |chunk|
      web = chunk["web"]
      next unless web.present?

      citations << {
        "url" => Raif::Utils::HtmlFragmentProcessor.strip_tracking_parameters(web["uri"]),
        "title" => web["title"]
      }
    end

    citations.uniq { |citation| citation["url"] }
  end

end
