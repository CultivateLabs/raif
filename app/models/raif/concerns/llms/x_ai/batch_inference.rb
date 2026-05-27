# frozen_string_literal: true

require "faraday/multipart"
require "stringio"

# xAI Batch API support for Raif::Llms::XAi.
# Implements the Raif::Concerns::Llms::SupportsBatchInference contract on top
# of /v1/files (multipart JSONL upload) and /v1/batches.
#
# xAI's Batch API supports two submission flows; we use the JSONL file-upload
# flow because it lets us send each per-request body in /v1/chat/completions
# shape (with `messages`), matching the sync path verbatim. The alternate REST
# append flow (POST /v1/batches/{id}/requests) only accepts the `responses`
# wrapper, which targets xAI's Responses API and would force a body-shape
# conversion (messages -> input, response_format -> text.format, ...).
#
# Submission flow:
#
#   POST /v1/files                        -> multipart upload of the JSONL,
#                                            returns { id: "file-..." }
#   POST /v1/batches { input_file_id }    -> creates the batch, returns
#                                            { batch_id, state: {...} }
#   GET  /v1/batches/{id}                 -> status (counts: pending/success/error/cancelled)
#   GET  /v1/batches/{id}/results         -> paginated per-entry results
#   POST /v1/batches/{id}:cancel          -> cancels pending entries
#
# Result envelope per entry (same for both submission flows):
#
#   {
#     "batch_request_id": "...",
#     "batch_result": {
#       "response": {
#         "chat_get_completion": { "id": ..., "choices": [...], "usage": {...} }
#       }
#     }
#   }
#
# The chat_get_completion payload matches the synchronous /v1/chat/completions
# response shape, so we feed it through the host class's #update_model_completion
# verbatim (the same parser used by the sync and streaming paths). Failures
# carry an "error" / "error_message" field instead of "response".
#
# xAI has no batch-level state enum: terminal is derived locally from
# num_pending hitting zero (or an explicit cancel acknowledgement, or
# expires_at elapsing).
module Raif::Concerns::Llms::XAi::BatchInference
  extend ActiveSupport::Concern

  include Raif::Concerns::Llms::SupportsBatchInference

  def batch_class
    Raif::ModelCompletionBatches::XAi
  end

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
        req.body = { name: "raif_batch_#{batch.id}", input_file_id: input_file_id }
      end
    end
    body = response.body.is_a?(Hash) ? response.body : {}
    provider_batch_id = body["batch_id"] || body["id"]

    if provider_batch_id.blank?
      raise Raif::Errors::InvalidBatchError,
        "xAI batch create returned no batch id (body=#{response.body.inspect})"
    end

    submitted_at = Time.current

    Raif::ModelCompletionBatch.transaction do
      batch.update!(
        provider_batch_id: provider_batch_id,
        status: "submitted",
        submitted_at: submitted_at,
        started_at: submitted_at,
        provider_response: (batch.provider_response || {}).merge(
          "input_file_id" => input_file_id,
          "expires_at" => body["expires_at"],
          "cost_breakdown" => body["cost_breakdown"]
        ).compact,
        request_counts: derive_request_counts(body) || batch.request_counts
      )

      batch.raif_model_completions.where(started_at: nil).update_all(started_at: submitted_at)
    end

    batch
  end

  def fetch_batch_status!(batch)
    response = with_batch_transient_retry(:fetch_status, batch_id: batch.id) do
      batch_connection.get("batches/#{batch.provider_batch_id}")
    end
    body = response.body
    new_status = derive_batch_status(body, batch)

    batch.with_lock do
      return batch.status if batch.terminal?

      provider_response_updates = (batch.provider_response || {}).merge(
        "expires_at" => body["expires_at"],
        "cost_breakdown" => body["cost_breakdown"]
      ).compact

      updates = {
        status: new_status,
        request_counts: derive_request_counts(body) || batch.request_counts,
        provider_response: provider_response_updates
      }
      if Raif::ModelCompletionBatch::TERMINAL_STATUSES.include?(new_status) && batch.ended_at.nil?
        updates[:ended_at] = Time.current
      end

      batch.update!(updates)
    end

    new_status
  end

  # Cancellation is fire-and-forget for pending entries -- xAI continues to
  # serve already-processed results, but no further entries are processed.
  # The provider response after a cancel may still report num_pending > 0
  # if the in-flight cancel hasn't propagated yet; treat as transitional
  # in_progress until counts settle.
  def cancel_batch!(batch)
    raise Raif::Errors::InvalidBatchError, "Batch ##{batch.id} has no provider_batch_id" if batch.provider_batch_id.blank?
    raise Raif::Errors::InvalidBatchError, "Batch ##{batch.id} is already terminal (status=#{batch.status})" if batch.terminal?

    response = with_batch_transient_retry(:cancel, batch_id: batch.id) do
      batch_connection.post("batches/#{batch.provider_batch_id}:cancel")
    end
    body = response.body
    new_status = derive_batch_status(body, batch, post_cancel: true)

    batch.with_lock do
      return batch.status if batch.terminal?

      provider_response_updates = (batch.provider_response || {}).merge(
        "expires_at" => body["expires_at"],
        "cost_breakdown" => body["cost_breakdown"]
      ).compact

      updates = {
        status: new_status,
        request_counts: derive_request_counts(body) || batch.request_counts,
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

    pagination_token = nil
    loop do
      params = {}
      params[:pagination_token] = pagination_token if pagination_token.present?

      response = with_batch_transient_retry(:fetch_results_page, batch_id: batch.id) do
        batch_connection.get("batches/#{batch.provider_batch_id}/results", params)
      end
      body = response.body || {}

      Array(body["results"]).each do |raw|
        custom_id = raw["batch_request_id"]
        mc = completions_by_id[custom_id]
        if mc.nil?
          Raif.logger.warn(
            "xAI batch results: batch_request_id #{custom_id.inspect} did not match any child completion in batch ##{batch.id}"
          )
          next
        end

        apply_batch_result(mc, raw)
      end

      pagination_token = body["pagination_token"].presence
      break if pagination_token.nil?
    end

    completions_by_id.each_value do |mc|
      mc.reload
      next if mc.completed? || mc.failed?

      mc.started_at ||= batch.started_at
      mc.failure_error = "xAI batch entry missing"
      mc.failure_reason = "Result not present in /results stream (batch ##{batch.id})"
      mc.failed!
    end

    batch.recalculate_costs!
    batch
  end

  # Applies one per-entry xAI batch result envelope to a Raif::ModelCompletion.
  # The success path feeds batch_result.response.chat_get_completion through the
  # host class's #update_model_completion (same parser used by the sync path),
  # so token counts, tool calls, and response shape are populated identically.
  # The 50% batch discount is applied automatically by
  # Raif::ModelCompletion#calculate_costs.
  def apply_batch_result(mc, raw_result)
    batch_result = raw_result["batch_result"] || {}
    response_envelope = batch_result["response"] || raw_result["response"]
    error_envelope = batch_result["error"] || raw_result["error"] || raw_result["error_message"]

    mc.started_at ||= mc.raif_model_completion_batch&.started_at || Time.current

    chat_payload = response_envelope.is_a?(Hash) ? response_envelope["chat_get_completion"] : nil

    if chat_payload.is_a?(Hash)
      update_model_completion(mc, chat_payload)
      mc.completed!
    else
      err_message = if error_envelope.is_a?(Hash)
        error_envelope["message"] || error_envelope["error_message"]
      else
        error_envelope
      end

      mc.failure_error = "xAI batch entry failed"
      mc.failure_reason = (err_message.presence || "unknown xAI batch failure").to_s.truncate(255)
      mc.failed!
    end

    mc
  end

private

  def batch_connection
    @batch_connection ||= Faraday.new(url: Raif.config.x_ai_base_url, request: Raif.default_request_options) do |f|
      f.headers["Authorization"] = "Bearer #{Raif.config.x_ai_api_key}"
      f.request :json
      f.response :json
      f.response :raise_error
    end
  end

  # Faraday connection for /v1/files JSONL uploads. Uses faraday-multipart so we
  # can pass a Faraday::Multipart::FilePart and let the middleware handle
  # boundary generation and content-disposition framing. xAI's /v1/files takes
  # only the file part -- no `purpose` field, unlike OpenAI.
  def batch_files_upload_connection
    @batch_files_upload_connection ||= Faraday.new(url: Raif.config.x_ai_base_url, request: Raif.default_request_options) do |f|
      f.headers["Authorization"] = "Bearer #{Raif.config.x_ai_api_key}"
      f.request :multipart
      f.request :url_encoded
      f.response :json
      f.response :raise_error
    end
  end

  # xAI batch input is a JSONL file. Each line:
  #   { custom_id, method: "POST", url: "/v1/chat/completions", body: <build_request_parameters> }
  # The body matches what the synchronous endpoint would receive verbatim, so
  # tools, response_format, and other chat-completions fields all work without
  # any batch-specific conversion. xAI maps the JSONL `custom_id` to
  # `batch_request_id` in /results, which is what fetch_batch_results! reads.
  def build_batch_jsonl(completions)
    completions.map do |mc|
      if mc.batch_custom_id.blank?
        raise Raif::Errors::InvalidBatchError, "Raif::ModelCompletion ##{mc.id} has blank batch_custom_id"
      end

      body = build_request_parameters(mc)
      body.delete(:stream)
      body.delete(:stream_options)

      {
        custom_id: mc.batch_custom_id,
        method: "POST",
        url: "/v1/chat/completions",
        body: body
      }.to_json
    end.join("\n")
  end

  # Uploads a JSONL string to /v1/files and returns the resulting file id.
  def upload_batch_input_file!(jsonl_string)
    file_part = Faraday::Multipart::FilePart.new(
      StringIO.new(jsonl_string),
      "application/jsonl",
      "batch.jsonl"
    )

    response = batch_files_upload_connection.post("files") do |req|
      req.body = { file: file_part }
    end

    body = response.body.is_a?(Hash) ? response.body : {}
    file_id = body["id"] || body["file_id"]
    if file_id.blank?
      raise Raif::Errors::InvalidBatchError,
        "xAI /v1/files upload returned no file id (body=#{response.body.inspect})"
    end

    file_id
  end

  # Returns nil when the response body has no usable state counts, so callers
  # can fall back to the previously-persisted batch.request_counts instead of
  # clobbering them with {} when xAI returns a sparse body (early-state
  # batches, transitional cancel acks, etc.).
  def derive_request_counts(body)
    state = body.is_a?(Hash) ? body["state"] : nil
    return unless state.is_a?(Hash)

    counts = {
      "total" => state["num_requests"],
      "pending" => state["num_pending"],
      "success" => state["num_success"],
      "error" => state["num_error"],
      "cancelled" => state["num_cancelled"]
    }.compact

    counts.presence
  end

  # xAI has no batch-level status enum. We derive a Raif status from the
  # counts in `state` plus a couple of out-of-band signals:
  #   - if num_pending == 0, the batch is terminal (every entry has either
  #     succeeded, errored, or been cancelled)
  #   - distinguish `canceled` vs `ended` by whether any entries were
  #     short-circuited by a cancel (num_cancelled > 0)
  #   - if expires_at is past while entries are still pending, treat as `expired`
  def derive_batch_status(body, _batch, post_cancel: false)
    return "in_progress" unless body.is_a?(Hash)

    state = body["state"] || {}
    num_pending = state["num_pending"]
    num_cancelled = state["num_cancelled"].to_i

    expires_at = parse_time(body["expires_at"])
    if expires_at && Time.current >= expires_at && num_pending.to_i > 0
      return "expired"
    end

    return "in_progress" if num_pending.nil? || num_pending.to_i > 0

    if post_cancel || num_cancelled > 0
      "canceled"
    else
      "ended"
    end
  end

  def parse_time(value)
    return if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
