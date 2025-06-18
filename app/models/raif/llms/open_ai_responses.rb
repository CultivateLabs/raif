# frozen_string_literal: true

class Raif::Llms::OpenAiResponses < Raif::Llms::OpenAiBase
  include Raif::Concerns::Llms::OpenAiResponses::MessageFormatting
  include Raif::Concerns::Llms::OpenAiResponses::ToolFormatting

private

  def api_path
    "responses"
  end

  def streaming_response_type
    Raif::StreamingResponses::OpenAiResponses
  end

  def update_model_completion(model_completion, response_json)
    model_completion.update!(
      response_id: response_json["id"],
      response_tool_calls: extract_response_tool_calls(response_json),
      raw_response: extract_raw_response(response_json),
      response_array: response_json["output"],
      citations: extract_citations(response_json),
      completion_tokens: response_json.dig("usage", "output_tokens"),
      prompt_tokens: response_json.dig("usage", "input_tokens"),
      total_tokens: response_json.dig("usage", "total_tokens")
    )
  end

  def extract_response_tool_calls(resp)
    return if resp["output"].blank?

    tool_calls = []
    resp["output"].each do |output_item|
      next unless output_item["type"] == "function_call"

      tool_calls << {
        "name" => output_item["name"],
        "arguments" => JSON.parse(output_item["arguments"])
      }
    end

    tool_calls.any? ? tool_calls : nil
  end

  def extract_raw_response(resp)
    text_outputs = []

    output_messages = resp["output"]&.select{ |output_item| output_item["type"] == "message" }
    output_messages&.each do |output_message|
      output_message["content"].each do |content_item|
        text_outputs << content_item["text"] if content_item["type"] == "output_text"
      end
    end

    text_outputs.join("\n").presence
  end

  def extract_citations(resp)
    return [] if resp["output"].blank?

    citations = []

    # Look through output messages for citations in annotations
    output_messages = resp["output"].select{|output_item| output_item["type"] == "message" }
    output_messages.each do |output_message|
      next unless output_message["content"].present?

      output_message["content"].each do |content_item|
        next unless content_item["type"] == "output_text" && content_item["annotations"].present?

        content_item["annotations"].each do |annotation|
          next unless annotation["type"] == "url_citation"

          citations << {
            "url" => Raif::Utils::HtmlFragmentProcessor.strip_tracking_parameters(annotation["url"]),
            "title" => annotation["title"]
          }
        end
      end
    end

    citations.uniq{|citation| citation["url"] }
  end

  def build_request_parameters(model_completion)
    parameters = {
      model: api_name,
      input: model_completion.messages,
    }

    if supports_temperature?
      parameters[:temperature] = model_completion.temperature.to_f
    end

    parameters[:stream] = true if model_completion.stream_response?

    # Add instructions (system prompt) if present
    formatted_system_prompt = format_system_prompt(model_completion)
    if formatted_system_prompt.present?
      parameters[:instructions] = formatted_system_prompt
    end

    # Add max_output_tokens if specified
    if model_completion.max_completion_tokens.present?
      parameters[:max_output_tokens] = model_completion.max_completion_tokens
    end

    # If the LLM supports native tool use and there are available tools, add them to the parameters
    if supports_native_tool_use?
      tools = build_tools_parameter(model_completion)
      parameters[:tools] = tools unless tools.blank?
    end

    # Add response format if needed. Default will be { "type": "text" }
    response_format = determine_response_format(model_completion)
    if response_format.present?
      parameters[:text] = { format: response_format }
    end

    parameters
  end

  def determine_response_format(model_completion)
    # Only configure response format for JSON outputs
    return unless model_completion.response_format_json?

    if model_completion.json_response_schema.present? && supports_structured_outputs?
      validate_json_schema!(model_completion.json_response_schema)

      {
        type: "json_schema",
        name: "json_response_schema",
        strict: true,
        schema: model_completion.json_response_schema
      }
    else
      # Default JSON mode for OpenAI models that don't support structured outputs or no schema is provided
      { type: "json_object" }
    end
  end

end
