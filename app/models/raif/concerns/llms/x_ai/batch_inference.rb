# frozen_string_literal: true

# xAI Batch API support for Raif::Llms::XAi.
# Implements the Raif::Concerns::Llms::SupportsBatchInference contract on top
# of /v1/batches and the per-request REST add path.
#
# xAI's Batch API uses a two-call submission flow with no file upload required:
#
#   POST /v1/batches                 -> creates an empty batch, returns batch_id
#   POST /v1/batches/{id}/requests   -> appends an array of batch_requests;
#                                       processing begins as soon as items are added
#   GET  /v1/batches/{id}            -> status (counts: pending/success/error/cancelled)
#   GET  /v1/batches/{id}/results    -> paginated per-entry results
#   POST /v1/batches/{id}:cancel     -> cancels pending entries
#
# Result envelope per entry:
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

  # Max batch_requests items sent in a single POST /v1/batches/{id}/requests
  # call. Chunked client-side so a single large batch turns into a sequence of
  # smaller add-requests calls. 500 is conservative -- xAI documents 50k
  # requests per batch in aggregate but doesn't publish a per-call limit.
  XAI_BATCH_REQUESTS_CHUNK_SIZE = 500

  def batch_class
    Raif::ModelCompletionBatches::XAi
  end

  def submit_batch!(batch)
    batch.assert_submittable!

    completions = batch.raif_model_completions.to_a
    raise Raif::Errors::InvalidBatchError, "Batch ##{batch.id} has no child completions" if completions.empty?

    completions.each do |mc|
      if mc.batch_custom_id.blank?
        raise Raif::Errors::InvalidBatchError, "Raif::ModelCompletion ##{mc.id} has blank batch_custom_id"
      end
    end

    create_response = batch_connection.post("batches") do |req|
      req.body = { name: "raif_batch_#{batch.id}" }
    end
    create_body = create_response.body
    provider_batch_id = create_body["batch_id"] || create_body["id"]

    if provider_batch_id.blank?
      raise Raif::Errors::InvalidBatchError,
        "xAI batch create returned no batch id (body=#{create_body.inspect})"
    end

    # Persist provider_batch_id immediately after the create call so a mid-
    # submission failure during chunked add-requests leaves the batch
    # recoverable (cancelable / pollable) rather than orphaned on xAI's side.
    batch.update!(provider_batch_id: provider_batch_id)

    last_add_body = nil
    completions.each_slice(XAI_BATCH_REQUESTS_CHUNK_SIZE) do |slice|
      payload = {
        batch_requests: slice.map { |mc| { batch_request_id: mc.batch_custom_id, batch_request: build_batch_request(mc) } }
      }

      response = batch_connection.post("batches/#{provider_batch_id}/requests") do |req|
        req.body = payload
      end
      last_add_body = response.body
    end

    submitted_at = Time.current

    Raif::ModelCompletionBatch.transaction do
      batch.update!(
        status: "submitted",
        submitted_at: submitted_at,
        started_at: submitted_at,
        provider_response: (batch.provider_response || {}).merge(
          "expires_at" => create_body["expires_at"] || last_add_body&.dig("expires_at"),
          "cost_breakdown" => last_add_body&.dig("cost_breakdown") || create_body["cost_breakdown"]
        ).compact,
        request_counts: derive_request_counts(last_add_body || create_body) || batch.request_counts
      )

      batch.raif_model_completions.where(started_at: nil).update_all(started_at: submitted_at)
    end

    batch
  end

  def fetch_batch_status!(batch)
    response = batch_connection.get("batches/#{batch.provider_batch_id}")
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

    response = batch_connection.post("batches/#{batch.provider_batch_id}:cancel")
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

      response = batch_connection.get("batches/#{batch.provider_batch_id}/results", params)
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

  # Builds the batch_request payload for one model completion. xAI's REST
  # add-requests endpoint expects each entry under a response-type key
  # (responses / image_generation / video_generation / ...). For chat we wrap
  # the chat-completions body inside `responses` per the xAI docs example;
  # `messages` is documented as accepted alongside `model` for this wrapper.
  # Streaming and stream_options are stripped -- batch entries are never
  # streamed.
  def build_batch_request(mc)
    body = build_request_parameters(mc)
    body.delete(:stream)
    body.delete(:stream_options)

    { responses: body }
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
