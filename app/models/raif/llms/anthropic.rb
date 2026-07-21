# frozen_string_literal: true

class Raif::Llms::Anthropic < Raif::Llm
  include Raif::Concerns::Llms::Anthropic::MessageFormatting
  include Raif::Concerns::Llms::Anthropic::ToolFormatting
  include Raif::Concerns::Llms::Anthropic::ResponseToolCalls
  include Raif::Concerns::Llms::Anthropic::BatchInference

  def self.prompt_tokens_include_cached_tokens?
    false
  end

  def self.cache_read_input_token_cost_multiplier
    0.1
  end

  def self.cache_creation_input_token_cost_multiplier
    1.25
  end

  def perform_model_completion!(model_completion, &block)
    params = build_request_parameters(model_completion)
    response = connection.post("messages") do |req|
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
    @connection ||= Faraday.new(url: "https://api.anthropic.com/v1", request: Raif.default_request_options) do |f|
      f.headers["x-api-key"] = Raif.config.anthropic_api_key
      f.headers["anthropic-version"] = "2023-06-01"
      f.request :json
      f.response :json
      f.response :raise_error
    end
  end

  def streaming_response_type
    Raif::StreamingResponses::Anthropic
  end

  def update_model_completion(model_completion, response_json)
    model_completion.raw_response = if model_completion.response_format_json?
      extract_json_response(response_json, model_completion)
    else
      extract_text_response(response_json)
    end

    model_completion.response_id = response_json&.dig("id")
    model_completion.response_finish_reason = response_json&.dig("stop_reason")
    model_completion.response_array = response_json&.dig("content")
    model_completion.response_tool_calls = extract_response_tool_calls(response_json)
    model_completion.citations = extract_citations(response_json)
    model_completion.completion_tokens = response_json&.dig("usage", "output_tokens")
    model_completion.prompt_tokens = response_json&.dig("usage", "input_tokens")
    model_completion.total_tokens = model_completion.completion_tokens.to_i + model_completion.prompt_tokens.to_i
    model_completion.cache_read_input_tokens = response_json&.dig("usage", "cache_read_input_tokens")
    model_completion.cache_creation_input_tokens = response_json&.dig("usage", "cache_creation_input_tokens")
    model_completion.save!
    validate_native_json_response!(model_completion)
  end

  def build_request_parameters(model_completion)
    params = {
      model: model_completion.model_api_name,
      messages: model_completion.messages
    }

    params[:temperature] = (model_completion.temperature || default_temperature).to_f if supports_temperature?
    params[:max_tokens] = model_completion.max_completion_tokens || default_max_completion_tokens

    params[:system] = model_completion.system_prompt if model_completion.system_prompt.present?
    params[:cache_control] = { type: "ephemeral" } if model_completion.anthropic_prompt_caching_enabled

    if supports_native_tool_use?
      tools = build_tools_parameter(model_completion)
      params[:tools] = tools unless tools.blank?

      if model_completion.tool_choice == "required"
        params[:tool_choice] = build_required_tool_choice(disable_parallel: model_completion.allow_parallel_tool_calls != true)
      elsif model_completion.tool_choice.present?
        tool_klass = model_completion.tool_choice.constantize
        params[:tool_choice] = build_forced_tool_choice(tool_klass.tool_name)
      end
    end

    if use_native_structured_outputs?(model_completion)
      params[:output_config] = {
        format: {
          type: "json_schema",
          schema: Raif::Llms::Anthropic::StrictSchemaTransformer.call(model_completion.json_response_schema)
        }
      }
      model_completion.response_format_parameter = "json_schema"
    end

    params[:stream] = true if model_completion.stream_response?

    params
  end

  def supports_temperature?
    provider_settings.key?(:supports_temperature) ? provider_settings[:supports_temperature] : true
  end

  def supports_structured_outputs?
    provider_settings.fetch(:supports_structured_outputs, false)
  end

  # Anthropic documents `output_config.format` as incompatible with citations.
  # Provider-managed WebSearch always enables citations, and `extract_citations`
  # parses `web_search_result_location` annotations from text content blocks.
  # When WebSearch is enabled, fall back to the synthetic `json_response` tool
  # path so the request remains valid and citation parsing can keep working.
  def uses_provider_managed_web_search?(model_completion)
    Array(model_completion.available_model_tools).any? do |tool|
      tool.to_s == Raif::ModelTools::ProviderManaged::WebSearch.to_s
    end
  end

  def use_native_structured_outputs?(model_completion)
    return false unless supports_structured_outputs?
    return false unless model_completion.response_format_json?
    return false if model_completion.json_response_schema.blank?
    return false if uses_provider_managed_web_search?(model_completion)

    true
  end

  def validate_native_json_response!(model_completion)
    return unless use_native_structured_outputs?(model_completion)
    return if model_completion.response_finish_reason.blank?
    return if model_completion.raw_response.blank?
    return if model_completion.response_tool_calls.present?

    validation_errors = JSON::Validator.fully_validate(
      model_completion.json_response_schema,
      model_completion.parsed_response(force_reparse: true)
    )
    return if validation_errors.empty?

    raise Raif::Errors::InvalidJsonResponseError,
      "Native JSON response did not satisfy the original schema: #{validation_errors.join("; ")}"
  rescue JSON::ParserError => e
    raise Raif::Errors::InvalidJsonResponseError,
      "Native JSON response could not be parsed: #{e.message}"
  end

  def extract_text_response(resp)
    return if resp&.dig("content").blank?

    resp.dig("content").select{|v| v["type"] == "text" }.map{|v| v["text"] }.join("\n")
  end

  def extract_json_response(resp, model_completion = nil)
    return extract_text_response(resp) if resp&.dig("content").nil?

    # Look for tool_use blocks in the content array
    tool_response = resp&.dig("content")&.find do |content|
      content["type"] == "tool_use" && content["name"] == "json_response"
    end

    if tool_response
      input = Raif::Llms::SyntheticJsonResponseToolInputNormalizer.call(
        input: tool_response["input"],
        schema: model_completion&.json_response_schema
      )
      return JSON.generate(input) if input
    end

    extract_text_response(resp)
  end

  def extract_citations(resp)
    return [] if resp&.dig("content").nil?

    citations = []

    # Look through content blocks for citations
    resp.dig("content").each do |content|
      next unless content["type"] == "text" && content["citations"].present?

      content["citations"].each do |citation|
        next unless citation["type"] == "web_search_result_location"

        citations << {
          "url" => Raif::Utils::HtmlFragmentProcessor.strip_tracking_parameters(citation["url"]),
          "title" => citation["title"]
        }
      end
    end

    citations.uniq{|citation| citation["url"] }
  end

end
