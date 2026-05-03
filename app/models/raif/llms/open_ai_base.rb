# frozen_string_literal: true

class Raif::Llms::OpenAiBase < Raif::Llm
  include Raif::Concerns::Llms::OpenAi::JsonSchemaValidation
  include Raif::Concerns::Llms::SupportsBatchInference

  def self.cache_read_input_token_cost_multiplier
    0.5
  end

  def perform_model_completion!(model_completion, &block)
    if supports_temperature?
      model_completion.temperature ||= default_temperature
    else
      Raif.logger.warn "Temperature is not supported for #{api_name}. Ignoring temperature parameter."
      model_completion.temperature = nil
    end

    parameters = build_request_parameters(model_completion)

    response = connection.post(api_path) do |req|
      req.body = parameters
      req.options.on_data = streaming_chunk_handler(model_completion, &block) if model_completion.stream_response?
    end

    unless model_completion.stream_response?
      update_model_completion(model_completion, response.body)
    end

    model_completion
  end

  def batch_class
    Raif::ModelCompletionBatches::OpenAi
  end

  # Subclasses override to declare which OpenAI endpoint they target. The same
  # value is used both as the JSONL line's `url` field (per-request endpoint)
  # and as the OpenAI Batches API `endpoint` parameter (whole-batch endpoint).
  # @return [String] e.g. "/v1/responses" or "/v1/chat/completions"
  def batch_endpoint_path
    raise NotImplementedError, "#{self.class.name} must implement #batch_endpoint_path"
  end

  # Submits all child Raif::ModelCompletion records as a single OpenAI batch.
  # Three-step flow: build the JSONL string, upload it as a file with
  # purpose=batch, then create the batch referencing the file.
  def submit_batch!(batch)
    completions = batch.raif_model_completions.to_a
    raise Raif::Errors::InvalidBatchError, "Batch ##{batch.id} has no child completions" if completions.empty?

    jsonl = build_batch_jsonl(completions)
    input_file_id = upload_batch_input_file!(jsonl)

    response = batch_connection.post("batches") do |req|
      req.body = {
        input_file_id: input_file_id,
        endpoint: batch_endpoint_path,
        completion_window: Raif.config.open_ai_batch_completion_window
      }
    end

    body = response.body
    submitted_at = Time.current
    batch.update!(
      provider_batch_id: body["id"],
      status: map_batch_status(body["status"]) || "submitted",
      submitted_at: submitted_at,
      started_at: submitted_at,
      provider_response: (batch.provider_response || {}).merge(
        "input_file_id" => input_file_id,
        "endpoint" => batch_endpoint_path
      ),
      request_counts: body["request_counts"] || {}
    )

    completions.each do |mc|
      mc.update_columns(started_at: submitted_at) if mc.started_at.nil?
    end

    batch
  end

  def fetch_batch_status!(batch)
    response = batch_connection.get("batches/#{batch.provider_batch_id}")
    body = response.body
    new_status = map_batch_status(body["status"])

    provider_response_updates = (batch.provider_response || {}).merge(
      "output_file_id" => body["output_file_id"],
      "error_file_id" => body["error_file_id"]
    )

    updates = {
      status: new_status,
      request_counts: body["request_counts"] || {},
      provider_response: provider_response_updates
    }
    if Raif::ModelCompletionBatch::TERMINAL_STATUSES.include?(new_status) && batch.ended_at.nil?
      updates[:ended_at] = Time.current
    end

    batch.update!(updates)
    new_status
  end

  def fetch_batch_results!(batch)
    completions_by_id = batch.raif_model_completions.index_by(&:provider_request_id)

    if batch.output_file_id.present?
      apply_batch_jsonl(batch, batch.output_file_id, completions_by_id)
    end

    # The error_file_id contains entries that errored before the model produced
    # a response (validation failures, request shape errors, etc.). These have
    # the same `{ id, custom_id, response, error }` envelope as the output file.
    if batch.error_file_id.present?
      apply_batch_jsonl(batch, batch.error_file_id, completions_by_id)
    end

    # Anything that was never reported in either file (rare; possible if the
    # batch expired mid-flight or was canceled) is left as a failed completion
    # so the workflow can advance.
    completions_by_id.each_value do |mc|
      next unless mc.reload.pending?

      mc.failure_error = "OpenAI batch entry missing"
      mc.failure_reason = "Result not present in output_file or error_file (batch ##{batch.id})"
      mc.update_columns(started_at: batch.started_at) if mc.started_at.nil?
      mc.failed!
    end

    batch.recalculate_costs!
    batch
  end

  # Applies one per-entry batch result envelope to a Raif::ModelCompletion.
  # OpenAI's batch envelope is { id, custom_id, response: { status_code,
  # request_id, body }, error }. The success path delegates to the subclass's
  # existing #update_model_completion (the same one used by the synchronous and
  # streaming paths), so token counts, tool calls, and response shape match.
  # The 50% batch discount is applied automatically by
  # Raif::ModelCompletion#calculate_costs.
  def apply_batch_result(mc, raw_result)
    response_envelope = raw_result["response"]
    error_envelope = raw_result["error"]

    started_fallback = mc.raif_model_completion_batch&.started_at || Time.current
    mc.update_columns(started_at: started_fallback) if mc.started_at.nil?

    if response_envelope.is_a?(Hash) && (response_envelope["status_code"] || 200).to_i.between?(200, 299)
      update_model_completion(mc, response_envelope["body"])
      mc.completed!
    else
      err_message = if error_envelope.is_a?(Hash)
        error_envelope["message"]
      elsif response_envelope.is_a?(Hash)
        response_envelope.dig("body", "error", "message")
      end

      mc.failure_error = "OpenAI batch entry failed (status: #{response_envelope&.dig("status_code") || "unknown"})"
      mc.failure_reason = (err_message.presence || "unknown OpenAI batch failure").to_s.truncate(255)
      mc.failed!
    end

    mc
  end

private

  def connection
    @connection ||= begin
      conn = Faraday.new(url: Raif.config.open_ai_base_url, request: Raif.default_request_options) do |f|
        case Raif.config.open_ai_auth_header_style
        when :bearer
          f.headers["Authorization"] = "Bearer #{Raif.config.open_ai_api_key}"
        when :api_key
          f.headers["api-key"] = Raif.config.open_ai_api_key
        else
          raise Raif::Errors::InvalidConfigError,
            "Raif.config.open_ai_auth_header_style must be either :bearer or :api_key"
        end

        f.request :json
        f.response :json
        f.response :raise_error
      end

      conn.params["api-version"] = Raif.config.open_ai_api_version if Raif.config.open_ai_api_version.present?
      conn
    end
  end

  def format_system_prompt(model_completion)
    formatted_system_prompt = model_completion.system_prompt.to_s.strip

    # If the response format is JSON, we need to include "as json" in the system prompt.
    # OpenAI requires this and will throw an error if it's not included.
    if model_completion.response_format_json?
      # Ensure system prompt ends with a period if not empty
      if formatted_system_prompt.present? && !formatted_system_prompt.end_with?(".", "?", "!")
        formatted_system_prompt += "."
      end
      formatted_system_prompt += " Return your response as JSON."
      formatted_system_prompt.strip!
    end

    formatted_system_prompt
  end

  def supports_structured_outputs?
    # Not all OpenAI models support structured outputs:
    # https://platform.openai.com/docs/guides/structured-outputs?api-mode=chat#supported-models
    provider_settings.key?(:supports_structured_outputs) ? provider_settings[:supports_structured_outputs] : true
  end

  def supports_temperature?
    provider_settings.key?(:supports_temperature) ? provider_settings[:supports_temperature] : true
  end

  # Faraday connection for OpenAI batch endpoints. Reuses the same auth +
  # base_url config as the streaming/sync connection, but lives separately so
  # we don't accidentally send batch traffic with stream-aware middleware.
  def batch_connection
    @batch_connection ||= begin
      conn = Faraday.new(url: Raif.config.open_ai_base_url, request: Raif.default_request_options) do |f|
        configure_open_ai_auth!(f)
        f.request :json
        f.response :json
        f.response :raise_error
      end

      conn.params["api-version"] = Raif.config.open_ai_api_version if Raif.config.open_ai_api_version.present?
      conn
    end
  end

  # File downloads from /v1/files/:id/content return JSONL plain bytes (or
  # an arbitrary file payload), so this connection deliberately omits the
  # JSON parser middleware.
  def batch_files_download_connection
    @batch_files_download_connection ||= begin
      conn = Faraday.new(url: Raif.config.open_ai_base_url, request: Raif.default_request_options) do |f|
        configure_open_ai_auth!(f)
        f.response :raise_error
      end

      conn.params["api-version"] = Raif.config.open_ai_api_version if Raif.config.open_ai_api_version.present?
      conn
    end
  end

  def configure_open_ai_auth!(faraday)
    case Raif.config.open_ai_auth_header_style
    when :bearer
      faraday.headers["Authorization"] = "Bearer #{Raif.config.open_ai_api_key}"
    when :api_key
      faraday.headers["api-key"] = Raif.config.open_ai_api_key
    else
      raise Raif::Errors::InvalidConfigError,
        "Raif.config.open_ai_auth_header_style must be either :bearer or :api_key"
    end
  end

  # OpenAI batch input is a JSONL file. Each line:
  #   { custom_id, method: "POST", url: <batch_endpoint_path>, body: <build_request_parameters> }
  # The body matches what the synchronous endpoint would receive verbatim.
  def build_batch_jsonl(completions)
    completions.map do |mc|
      if mc.provider_request_id.blank?
        raise Raif::Errors::InvalidBatchError, "Raif::ModelCompletion ##{mc.id} has blank provider_request_id"
      end

      # Mirror perform_model_completion!'s temperature-coercion semantics so
      # the batch body matches what the sync path would send.
      mc.temperature ||= default_temperature if supports_temperature?
      mc.temperature = nil unless supports_temperature?

      {
        custom_id: mc.provider_request_id,
        method: "POST",
        url: batch_endpoint_path,
        body: build_request_parameters(mc)
      }.to_json
    end.join("\n")
  end

  # Uploads a JSONL string to /v1/files with purpose=batch and returns the
  # resulting file id. Builds the multipart/form-data body inline to avoid
  # depending on faraday-multipart.
  def upload_batch_input_file!(jsonl_string)
    boundary = "----RaifBatchUpload#{SecureRandom.hex(16)}"
    body = build_multipart_batch_body(boundary: boundary, jsonl_string: jsonl_string)

    response = batch_files_download_connection.post("files") do |req|
      req.headers["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      req.body = body
    end

    parsed = response.body.is_a?(String) ? JSON.parse(response.body) : response.body
    parsed.fetch("id")
  end

  def build_multipart_batch_body(boundary:, jsonl_string:)
    crlf = "\r\n"
    parts = []

    parts << "--#{boundary}"
    parts << 'Content-Disposition: form-data; name="purpose"'
    parts << ""
    parts << "batch"

    parts << "--#{boundary}"
    parts << 'Content-Disposition: form-data; name="file"; filename="batch.jsonl"'
    parts << "Content-Type: application/jsonl"
    parts << ""
    parts << jsonl_string

    parts << "--#{boundary}--"
    parts << ""

    parts.join(crlf)
  end

  # OpenAI batch.status -> Raif::ModelCompletionBatch::STATUSES.
  # https://platform.openai.com/docs/api-reference/batch/object
  def map_batch_status(provider_status)
    case provider_status
    when "validating", "in_progress", "finalizing", "cancelling" then "in_progress"
    when "completed" then "ended"
    when "failed" then "failed"
    when "expired" then "expired"
    when "cancelled" then "canceled"
    else "in_progress"
    end
  end

  def apply_batch_jsonl(batch, file_id, completions_by_id)
    response = batch_files_download_connection.get("files/#{file_id}/content")
    body = response.body.to_s

    body.each_line do |line|
      line = line.strip
      next if line.blank?

      raw = JSON.parse(line)
      custom_id = raw["custom_id"]
      mc = completions_by_id[custom_id]
      if mc.nil?
        Raif.logger.warn(
          "OpenAI batch results: custom_id #{custom_id.inspect} did not match any child completion in batch ##{batch.id}"
        )
        next
      end

      apply_batch_result(mc, raw)
    end
  end

end
