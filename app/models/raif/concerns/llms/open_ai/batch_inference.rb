# frozen_string_literal: true

require "faraday/multipart"
require "stringio"

# OpenAI Batches API support for Raif::Llms::OpenAiBase.
# Implements the Raif::Concerns::Llms::SupportsBatchInference contract on top
# of /v1/batches and the JSONL input/output file flow.
#
# The host LLM class is expected to provide #build_request_parameters,
# #update_model_completion, and #supports_temperature? -- these are reused
# verbatim from the synchronous path so request body and response parsing
# are identical between the sync and batch paths. Subclasses must also
# implement #batch_endpoint_path to declare which OpenAI endpoint to target.
module Raif::Concerns::Llms::OpenAi::BatchInference
  extend ActiveSupport::Concern

  include Raif::Concerns::Llms::SupportsBatchInference

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
  #
  # The batch + child writes happen in a transaction so a partial failure
  # (e.g. the network call succeeds but the child started_at update raises)
  # leaves no submitted-but-unstamped state behind.
  def submit_batch!(batch)
    batch.assert_submittable!

    completions = batch.raif_model_completions.to_a
    raise Raif::Errors::InvalidBatchError, "Batch ##{batch.id} has no child completions" if completions.empty?

    jsonl = build_batch_jsonl(completions)
    input_file_id = with_batch_transient_retry(:submit_upload_input, batch_id: batch.id) do
      upload_batch_input_file!(jsonl)
    end

    response = with_batch_transient_retry(:submit_create, batch_id: batch.id) do
      batch_connection.post("batches") do |req|
        req.body = {
          input_file_id: input_file_id,
          endpoint: batch_endpoint_path,
          completion_window: Raif.config.open_ai_batch_completion_window
        }
      end
    end

    body = response.body
    submitted_at = Time.current

    Raif::ModelCompletionBatch.transaction do
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

      # Single UPDATE for all children that don't already have a started_at,
      # filtered in SQL so we can't stomp a started_at that was set by another
      # process between when we loaded `completions` and now.
      batch.raif_model_completions.where(started_at: nil).update_all(started_at: submitted_at)
    end

    batch
  end

  def fetch_batch_status!(batch)
    response = with_batch_transient_retry(:fetch_status, batch_id: batch.id) do
      batch_connection.get("batches/#{batch.provider_batch_id}")
    end
    body = response.body
    new_status = map_batch_status(body["status"])

    # Re-acquire a row-level lock + reload so we don't overwrite a status another
    # process (e.g. ExpireStuckModelCompletionBatchesJob) just transitioned to
    # terminal. Without this guard, a stale instance can stomp a `failed`
    # decision back to whatever the provider currently reports.
    batch.with_lock do
      return batch.status if batch.terminal?

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
    end

    new_status
  end

  # Sends a cancel request to OpenAI's Batches API. Cancellation is
  # asynchronous on OpenAI's side: the provider transitions to status
  # "cancelling" first, then to "cancelled" (mapped to "canceled") once
  # in-flight entries finish. Returns the (possibly transitional) Raif status.
  def cancel_batch!(batch)
    raise Raif::Errors::InvalidBatchError, "Batch ##{batch.id} has no provider_batch_id" if batch.provider_batch_id.blank?
    raise Raif::Errors::InvalidBatchError, "Batch ##{batch.id} is already terminal (status=#{batch.status})" if batch.terminal?

    response = with_batch_transient_retry(:cancel, batch_id: batch.id) do
      batch_connection.post("batches/#{batch.provider_batch_id}/cancel")
    end
    body = response.body
    new_status = map_batch_status(body["status"])

    batch.with_lock do
      return batch.status if batch.terminal?

      provider_response_updates = (batch.provider_response || {}).merge(
        "output_file_id" => body["output_file_id"],
        "error_file_id" => body["error_file_id"]
      )

      updates = {
        status: new_status,
        request_counts: body["request_counts"] || batch.request_counts,
        provider_response: provider_response_updates
      }
      if Raif::ModelCompletionBatch::TERMINAL_STATUSES.include?(new_status) && batch.ended_at.nil?
        updates[:ended_at] = Time.current
      end

      batch.update!(updates)
    end

    new_status
  end

  def fetch_batch_results!(batch)
    completions_by_id = batch.raif_model_completions.index_by(&:batch_custom_id)

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
      mc.reload
      next if mc.completed? || mc.failed?

      mc.started_at ||= batch.started_at
      mc.failure_error = "OpenAI batch entry missing"
      mc.failure_reason = "Result not present in output_file or error_file (batch ##{batch.id})"
      mc.failed!
    end

    batch.recalculate_costs!
    batch
  end

  # Applies one per-entry batch result envelope to a Raif::ModelCompletion.
  # OpenAI's batch envelope is { id, custom_id, response: { status_code,
  # request_id, body }, error }. The success path delegates to the host class's
  # existing #update_model_completion (the same one used by the synchronous and
  # streaming paths), so token counts, tool calls, and response shape match.
  # The 50% batch discount is applied automatically by
  # Raif::ModelCompletion#calculate_costs.
  def apply_batch_result(mc, raw_result)
    response_envelope = raw_result["response"]
    error_envelope = raw_result["error"]

    # Set started_at in-memory before any save below, so update_model_completion's
    # save (or mc.failed!'s save) persists it in a single round-trip.
    mc.started_at ||= mc.raif_model_completion_batch&.started_at || Time.current

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

  # Faraday connection for OpenAI batch endpoints. Reuses the same auth +
  # base_url config as the streaming/sync connection, but lives separately so
  # we don't accidentally send batch traffic with stream-aware middleware.
  def batch_connection
    @batch_connection ||= begin
      conn = Faraday.new(url: Raif.config.open_ai_base_url, request: Raif.default_request_options) do |f|
        configure_open_ai_batch_auth!(f)
        f.request :json
        f.response :json
        f.response :raise_error
      end

      conn.params["api-version"] = Raif.config.open_ai_api_version if Raif.config.open_ai_api_version.present?
      conn
    end
  end

  # Faraday connection for /v1/files JSONL uploads. Uses faraday-multipart so we
  # can pass a Faraday::Multipart::FilePart and let the middleware handle
  # boundary generation and content-disposition framing.
  def batch_files_upload_connection
    @batch_files_upload_connection ||= begin
      conn = Faraday.new(url: Raif.config.open_ai_base_url, request: Raif.default_request_options) do |f|
        configure_open_ai_batch_auth!(f)
        f.request :multipart
        f.request :url_encoded
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
        configure_open_ai_batch_auth!(f)
        f.response :raise_error
      end

      conn.params["api-version"] = Raif.config.open_ai_api_version if Raif.config.open_ai_api_version.present?
      conn
    end
  end

  def configure_open_ai_batch_auth!(faraday)
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
      if mc.batch_custom_id.blank?
        raise Raif::Errors::InvalidBatchError, "Raif::ModelCompletion ##{mc.id} has blank batch_custom_id"
      end

      # Mirror perform_model_completion!'s temperature-coercion semantics so
      # the batch body matches what the sync path would send.
      mc.temperature ||= default_temperature if supports_temperature?
      mc.temperature = nil unless supports_temperature?

      {
        custom_id: mc.batch_custom_id,
        method: "POST",
        url: batch_endpoint_path,
        body: build_request_parameters(mc)
      }.to_json
    end.join("\n")
  end

  # Uploads a JSONL string to /v1/files with purpose=batch and returns the
  # resulting file id.
  def upload_batch_input_file!(jsonl_string)
    file_part = Faraday::Multipart::FilePart.new(
      StringIO.new(jsonl_string),
      "application/jsonl",
      "batch.jsonl"
    )

    response = batch_files_upload_connection.post("files") do |req|
      req.body = { purpose: "batch", file: file_part }
    end

    response.body.fetch("id")
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
    else
      Raif.logger.warn(
        "Raif::Concerns::Llms::OpenAi::BatchInference: unknown OpenAI batch status " \
          "#{provider_status.inspect}; treating as in_progress. The provider may have introduced a new " \
          "status that Raif doesn't yet recognize."
      )
      "in_progress"
    end
  end

  def apply_batch_jsonl(batch, file_id, completions_by_id)
    response = with_batch_transient_retry(:fetch_results_file, batch_id: batch.id) do
      batch_files_download_connection.get("files/#{file_id}/content")
    end
    body = response.body.to_s

    body.each_line do |line|
      line = line.strip
      next if line.blank?

      begin
        raw = JSON.parse(line)
      rescue JSON::ParserError => e
        # One bad line shouldn't poison the rest of the batch. Skip it; any
        # child completion that never gets matched falls through to the
        # missing-entry sweep in fetch_batch_results! and is force-failed there.
        Raif.logger.error(
          "OpenAI batch ##{batch.id} results: skipping malformed JSONL line " \
            "(#{e.class}: #{e.message}): #{line.inspect}"
        )
        next
      end

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
