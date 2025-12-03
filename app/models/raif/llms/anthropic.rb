# frozen_string_literal: true

class Raif::Llms::Anthropic < Raif::Llm
  include Raif::Concerns::Llms::Anthropic::MessageFormatting
  include Raif::Concerns::Llms::Anthropic::ToolFormatting
  include Raif::Concerns::Llms::Anthropic::ResponseToolCalls

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
    @connection ||= Faraday.new(url: "https://api.anthropic.com/v1") do |f|
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
      extract_json_response(response_json)
    else
      extract_text_response(response_json)
    end

    model_completion.response_id = response_json&.dig("id")
    model_completion.response_array = response_json&.dig("content")
    model_completion.response_tool_calls = extract_response_tool_calls(response_json)
    model_completion.citations = extract_citations(response_json)
    model_completion.completion_tokens = response_json&.dig("usage", "output_tokens")
    model_completion.prompt_tokens = response_json&.dig("usage", "input_tokens")
    model_completion.total_tokens = model_completion.completion_tokens.to_i + model_completion.prompt_tokens.to_i
    model_completion.save!
  end

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

      if model_completion.tool_choice.present?
        tool_klass = model_completion.tool_choice.constantize
        params[:tool_choice] = build_forced_tool_choice(tool_klass.tool_name)
      end
    end

    params[:stream] = true if model_completion.stream_response?

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
