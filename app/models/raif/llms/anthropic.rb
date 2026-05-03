# frozen_string_literal: true

class Raif::Llms::Anthropic < Raif::Llm
  include Raif::Concerns::Llms::Anthropic::MessageFormatting
  include Raif::Concerns::Llms::Anthropic::ToolFormatting
  include Raif::Concerns::Llms::Anthropic::ResponseToolCalls
  include Raif::Concerns::Llms::SupportsBatchInference

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

  def batch_class
    Raif::ModelCompletionBatches::Anthropic
  end

  # Submits all child Raif::ModelCompletion records of the batch as a single
  # Anthropic Messages Batch. Each entry's `params` body is identical to what the
  # synchronous /v1/messages endpoint would receive (built via #build_request_parameters),
  # so prompt caching, tool definitions, and response_format all carry over verbatim.
  def submit_batch!(batch)
    completions = batch.raif_model_completions.to_a
    raise Raif::Errors::InvalidBatchError, "Batch ##{batch.id} has no child completions" if completions.empty?

    requests = completions.map do |mc|
      if mc.provider_request_id.blank?
        raise Raif::Errors::InvalidBatchError, "Raif::ModelCompletion ##{mc.id} has blank provider_request_id"
      end

      { custom_id: mc.provider_request_id, params: build_request_parameters(mc) }
    end

    response = batch_connection.post("messages/batches") do |req|
      req.body = { requests: requests }
    end

    body = response.body
    submitted_at = Time.current
    batch.update!(
      provider_batch_id: body["id"],
      status: map_processing_status(body["processing_status"]) || "submitted",
      submitted_at: submitted_at,
      started_at: submitted_at,
      provider_response: (batch.provider_response || {}).merge(
        "results_url" => body["results_url"],
        "cancel_url" => body["cancel_url"]
      ),
      request_counts: body["request_counts"] || {}
    )

    completions.each do |mc|
      mc.update_columns(started_at: submitted_at) if mc.started_at.nil?
    end

    batch
  end

  def fetch_batch_status!(batch)
    response = batch_connection.get("messages/batches/#{batch.provider_batch_id}")
    body = response.body
    new_status = map_processing_status(body["processing_status"])

    updates = {
      status: new_status,
      request_counts: body["request_counts"] || {},
      provider_response: (batch.provider_response || {}).merge(
        "results_url" => body["results_url"],
        "cancel_url" => body["cancel_url"]
      )
    }
    if Raif::ModelCompletionBatch::TERMINAL_STATUSES.include?(new_status) && batch.ended_at.nil?
      updates[:ended_at] = Time.current
    end

    batch.update!(updates)
    new_status
  end

  def fetch_batch_results!(batch)
    raise Raif::Errors::InvalidBatchError, "Batch ##{batch.id} has no results_url" if batch.results_url.blank?

    completions_by_id = batch.raif_model_completions.index_by(&:provider_request_id)

    response = batch_results_connection.get(batch.results_url)
    body = response.body.to_s

    body.each_line do |line|
      line = line.strip
      next if line.blank?

      raw = JSON.parse(line)
      custom_id = raw["custom_id"]
      mc = completions_by_id[custom_id]
      if mc.nil?
        Raif.logger.warn(
          "Anthropic batch results: custom_id #{custom_id.inspect} did not match any child completion in batch ##{batch.id}"
        )
        next
      end

      apply_batch_result(mc, raw)
    end

    # Anything that was never reported in the results stream (rare; possible if
    # the batch expired mid-flight or was canceled) is force-failed so the
    # workflow can advance.
    completions_by_id.each_value do |mc|
      mc.reload
      next if mc.completed? || mc.failed?

      mc.failure_error = "Anthropic batch entry missing"
      mc.failure_reason = "Result not present in results stream (batch ##{batch.id})"
      mc.update_columns(started_at: batch.started_at) if mc.started_at.nil?
      mc.failed!
    end

    batch.recalculate_costs!
    batch
  end

  # Applies one per-entry batch result to a Raif::ModelCompletion. The success
  # path feeds the embedded `message` payload through update_model_completion --
  # the same parser used by the synchronous and streaming paths -- so token
  # counts, tool calls, citations, and response shape are populated identically.
  # The 50% Anthropic batch discount is applied automatically by
  # Raif::ModelCompletion#calculate_costs (because raif_model_completion_batch_id is set).
  def apply_batch_result(mc, raw_result)
    result = raw_result["result"] || {}
    started_fallback = mc.raif_model_completion_batch&.started_at || Time.current

    case result["type"]
    when "succeeded"
      update_model_completion(mc, result["message"])
      mc.update_columns(started_at: started_fallback) if mc.started_at.nil?
      mc.completed!
    else
      type = result["type"].to_s
      error = result["error"] || {}
      mc.failure_error = "Anthropic batch entry #{type.presence || "failed"}"
      mc.failure_reason = (error["message"].presence || type.presence || "unknown failure").to_s.truncate(255)
      mc.update_columns(started_at: started_fallback) if mc.started_at.nil?
      mc.failed!
    end

    mc
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

  def batch_connection
    @batch_connection ||= Faraday.new(url: "https://api.anthropic.com/v1", request: Raif.default_request_options) do |f|
      f.headers["x-api-key"] = Raif.config.anthropic_api_key
      f.headers["anthropic-version"] = "2023-06-01"
      if Raif.config.anthropic_message_batches_beta_header.present?
        f.headers["anthropic-beta"] = Raif.config.anthropic_message_batches_beta_header
      end
      f.request :json
      f.response :json
      f.response :raise_error
    end
  end

  # The results_url returned by the batches API serves JSONL, not JSON, and may
  # be served from a different host than /v1. Use a connection that does NOT
  # auto-parse the response body.
  def batch_results_connection
    @batch_results_connection ||= Faraday.new(request: Raif.default_request_options) do |f|
      f.headers["x-api-key"] = Raif.config.anthropic_api_key
      f.headers["anthropic-version"] = "2023-06-01"
      if Raif.config.anthropic_message_batches_beta_header.present?
        f.headers["anthropic-beta"] = Raif.config.anthropic_message_batches_beta_header
      end
      f.response :raise_error
    end
  end

  def map_processing_status(processing_status)
    case processing_status
    when "in_progress", "canceling" then "in_progress"
    when "ended" then "ended"
    when "canceled" then "canceled"
    when "expired" then "expired"
    else "in_progress"
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
    model_completion.cache_read_input_tokens = response_json&.dig("usage", "cache_read_input_tokens")
    model_completion.cache_creation_input_tokens = response_json&.dig("usage", "cache_creation_input_tokens")
    model_completion.save!
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
        params[:tool_choice] = build_required_tool_choice
      elsif model_completion.tool_choice.present?
        tool_klass = model_completion.tool_choice.constantize
        params[:tool_choice] = build_forced_tool_choice(tool_klass.tool_name)
      end
    end

    params[:stream] = true if model_completion.stream_response?

    params
  end

  def supports_temperature?
    provider_settings.key?(:supports_temperature) ? provider_settings[:supports_temperature] : true
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
