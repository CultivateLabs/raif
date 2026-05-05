# frozen_string_literal: true

# Google Gemini Batch API support for Raif::Llms::Google.
# Implements the Raif::Concerns::Llms::SupportsBatchInference contract on top
# of /v1beta/models/{model}:batchGenerateContent.
#
# v1 supports inline submission only (the Gemini "inlinedRequests" mode, with
# a 20MB per-batch limit). File-based submission via the Files API is a
# follow-up. The 20MB ceiling is enforced client-side with a clear error so a
# host hitting the limit gets pointed somewhere useful instead of an opaque
# 400 from Google.
#
# The host LLM class is expected to provide #build_request_parameters and
# #update_model_completion -- these are reused verbatim from the synchronous
# path so prompt caching, tool definitions, and response shape carry over.
#
# Response-shape note: the Gemini Batch API is a Google long-running operation
# (LRO). Different doc sources show the `state` field at slightly different
# paths (top-level vs nested under `metadata`), and the inline-results sub-tree
# similarly varies. The extraction helpers below try multiple paths and log
# when nothing matches so we degrade visibly rather than silently dropping
# results.
module Raif::Concerns::Llms::Google::BatchInference
  extend ActiveSupport::Concern

  include Raif::Concerns::Llms::SupportsBatchInference

  # Gemini's documented inline-request size limit. We measure the encoded JSON
  # body up-front so a too-big batch fails with a clear error rather than a
  # provider-side 400.
  INLINE_BATCH_MAX_BYTES = 20 * 1024 * 1024

  def batch_class
    Raif::ModelCompletionBatches::Google
  end

  # Submits all child Raif::ModelCompletion records of the batch as a single
  # Gemini batch via :batchGenerateContent (inline mode). Each entry's `request`
  # body is identical to what the synchronous /generateContent endpoint would
  # receive, with the per-request `metadata.key` carrying batch_custom_id so we
  # can match results back on completion.
  #
  # The batch + child writes happen in a transaction so a partial failure
  # (e.g. the network call succeeds but the child started_at update raises)
  # leaves no submitted-but-unstamped state behind.
  def submit_batch!(batch)
    batch.assert_submittable!

    completions = batch.raif_model_completions.to_a
    raise Raif::Errors::InvalidBatchError, "Batch ##{batch.id} has no child completions" if completions.empty?

    inline_requests = completions.map do |mc|
      if mc.batch_custom_id.blank?
        raise Raif::Errors::InvalidBatchError, "Raif::ModelCompletion ##{mc.id} has blank batch_custom_id"
      end

      { request: build_request_parameters(mc), metadata: { key: mc.batch_custom_id } }
    end

    body = {
      batch: {
        display_name: "raif-batch-#{batch.id}",
        input_config: {
          requests: { requests: inline_requests }
        }
      }
    }

    encoded = body.to_json
    if encoded.bytesize > INLINE_BATCH_MAX_BYTES
      raise Raif::Errors::InvalidBatchError,
        "Batch ##{batch.id} exceeds Gemini's #{INLINE_BATCH_MAX_BYTES} byte inline batch limit " \
          "(serialized: #{encoded.bytesize} bytes). File-based submission isn't implemented yet; " \
          "split the batch or open multiple batches."
    end

    response = batch_connection.post("models/#{batch.model_api_name}:batchGenerateContent") do |req|
      req.body = body
    end

    response_body = response.body
    operation_name = response_body["name"].to_s
    new_status = map_job_state(extract_state(response_body)) || "submitted"
    submitted_at = Time.current

    Raif::ModelCompletionBatch.transaction do
      batch.update!(
        provider_batch_id: extract_provider_batch_id(operation_name),
        status: new_status,
        submitted_at: submitted_at,
        started_at: submitted_at,
        provider_response: (batch.provider_response || {}).merge(
          "operation_name" => operation_name,
          "state" => extract_state(response_body),
          "done" => response_body["done"]
        ),
        request_counts: extract_request_counts(response_body)
      )

      # Single UPDATE for all children that don't already have a started_at,
      # filtered in SQL so we can't stomp a started_at that was set by another
      # process between when we loaded `completions` and now.
      batch.raif_model_completions.where(started_at: nil).update_all(started_at: submitted_at)
    end

    batch
  end

  def fetch_batch_status!(batch)
    response = batch_connection.get(batch.operation_name)
    body = response.body
    new_status = map_job_state(extract_state(body))

    # Re-acquire a row-level lock + reload so we don't overwrite a status another
    # process (e.g. ExpireStuckModelCompletionBatchesJob) just transitioned to
    # terminal. Without this guard, a stale instance can stomp a `failed`
    # decision back to whatever the provider currently reports.
    batch.with_lock do
      return batch.status if batch.terminal?

      provider_response_updates = (batch.provider_response || {}).merge(
        "operation_name" => batch.operation_name,
        "state" => extract_state(body),
        "done" => body["done"]
      )
      # Cache the operation's `response` sub-tree (which holds inlinedResponses
      # on a successful batch) so fetch_batch_results! doesn't have to re-poll.
      provider_response_updates["response"] = body["response"] if body["response"].present?

      updates = {
        status: new_status,
        request_counts: extract_request_counts(body),
        provider_response: provider_response_updates
      }
      if Raif::ModelCompletionBatch::TERMINAL_STATUSES.include?(new_status) && batch.ended_at.nil?
        updates[:ended_at] = Time.current
      end

      batch.update!(updates)
    end

    new_status
  end

  # Sends a cancel request to Gemini's Batch API. Cancellation is asynchronous
  # on Google's side: :cancel returns google.protobuf.Empty (an empty body) and
  # the operation transitions to JOB_STATE_CANCELLED on a later poll. We mark
  # the batch in_progress here and let the next fetch_batch_status! pick up the
  # final canceled state.
  def cancel_batch!(batch)
    raise Raif::Errors::InvalidBatchError, "Batch ##{batch.id} has no provider_batch_id" if batch.provider_batch_id.blank?
    raise Raif::Errors::InvalidBatchError, "Batch ##{batch.id} is already terminal (status=#{batch.status})" if batch.terminal?

    batch_connection.post("#{batch.operation_name}:cancel")

    batch.with_lock do
      return batch.status if batch.terminal?

      batch.update!(status: "in_progress")
    end

    batch.status
  end

  def fetch_batch_results!(batch)
    completions_by_id = batch.raif_model_completions.index_by(&:batch_custom_id)

    payload = batch.latest_response_payload
    if payload.blank?
      # Fall back to a direct fetch in case the polling job's status update
      # didn't capture the response sub-tree (e.g. the success transition
      # happened in a prior process and provider_response was cleared).
      response = batch_connection.get(batch.operation_name)
      payload = response.body["response"] || response.body
    end

    inlined_responses = extract_inlined_responses(payload)
    if inlined_responses.empty?
      Raif.logger.warn(
        "Raif::Concerns::Llms::Google::BatchInference: no inlinedResponses found in payload for batch ##{batch.id}; " \
          "every child completion will be force-failed below. Inspect provider_response to debug."
      )
    end

    inlined_responses.each do |entry|
      key = entry.dig("metadata", "key") || entry["key"]
      mc = completions_by_id[key]
      if mc.nil?
        Raif.logger.warn(
          "Google batch results: key #{key.inspect} did not match any child completion in batch ##{batch.id}"
        )
        next
      end

      apply_batch_result(mc, entry)
    end

    # Anything that was never reported in the inline results (rare; possible
    # if the batch expired mid-flight or was canceled) is force-failed so the
    # workflow can advance.
    completions_by_id.each_value do |mc|
      mc.reload
      next if mc.completed? || mc.failed?

      mc.started_at ||= batch.started_at
      mc.failure_error = "Google batch entry missing"
      mc.failure_reason = "Result not present in inlinedResponses (batch ##{batch.id})"
      mc.failed!
    end

    batch.recalculate_costs!
    batch
  end

  # Applies one per-entry batch result to a Raif::ModelCompletion. The success
  # path feeds the embedded GenerateContentResponse through update_model_completion --
  # the same parser used by the synchronous and streaming paths -- so token
  # counts, tool calls, citations, and response shape are populated identically.
  # The 50% Gemini batch discount is applied automatically by
  # Raif::ModelCompletion#calculate_costs (because raif_model_completion_batch_id is set).
  def apply_batch_result(mc, raw_result)
    response_payload = raw_result["response"]
    error_payload = raw_result["error"]
    status_obj = raw_result["status"] # alternate error encoding seen in some Google APIs

    # Set started_at in-memory before any save below, so update_model_completion's
    # save (or mc.failed!'s save) persists it in a single round-trip.
    mc.started_at ||= mc.raif_model_completion_batch&.started_at || Time.current

    if response_payload.is_a?(Hash) && error_payload.blank?
      update_model_completion(mc, response_payload)
      mc.completed!
    else
      err = error_payload.is_a?(Hash) ? error_payload : status_obj
      err_message = err.is_a?(Hash) ? err["message"] : nil
      err_code = err.is_a?(Hash) ? (err["code"] || err["status"]) : nil

      mc.failure_error = "Google batch entry failed#{err_code ? " (code: #{err_code})" : ""}"
      mc.failure_reason = (err_message.presence || "unknown Google batch failure").to_s.truncate(255)
      mc.failed!
    end

    mc
  end

private

  def batch_connection
    @batch_connection ||= Faraday.new(url: "https://generativelanguage.googleapis.com/v1beta", request: Raif.default_request_options) do |f|
      f.headers["x-goog-api-key"] = Raif.config.google_api_key
      f.request :json
      f.response :json
      f.response :raise_error
    end
  end

  # Strips the "batches/" prefix from an LRO resource name. Stored bare so the
  # provider_batch_id index matches the convention used by the other providers
  # (Anthropic stores "msgbatch_..." bare; OpenAI stores "batch_..." bare).
  def extract_provider_batch_id(operation_name)
    return if operation_name.blank?

    operation_name.to_s.sub(%r{\Abatches/}, "")
  end

  # Pulls the LRO state from either the LRO metadata wrapper or a top-level
  # `state` field. The Gemini docs show both shapes in different examples, so
  # check both rather than guessing.
  def extract_state(body)
    return unless body.is_a?(Hash)

    body.dig("metadata", "state") || body["state"]
  end

  # Pulls request counts (Gemini's `batchStats`) from either the LRO metadata
  # wrapper or a top-level field. Returns a hash so callers can store it
  # in jsonb without a nil guard.
  def extract_request_counts(body)
    return {} unless body.is_a?(Hash)

    body.dig("metadata", "batchStats") || body["batchStats"] || body["completionStats"] || {}
  end

  # The Gemini docs show inline results in a few different paths depending on
  # whether the response is unwrapped or shown as a raw LRO; the inner value
  # may itself be a `{ "inlinedResponses": [...] }` wrapper mirroring the
  # create-side `requests.requests` double-nesting. Try every shape we've seen.
  def extract_inlined_responses(payload)
    return [] unless payload.is_a?(Hash)

    # Each entry is either an Array (the flat shape) or a Hash that itself
    # holds a nested "inlinedResponses" array (the doubled shape mirroring
    # the create-side `requests.requests` wrapper). Avoid Hash#dig chains
    # past the first hop so we don't TypeError on the flat shape.
    candidates = [
      payload["inlinedResponses"],
      payload.dig("response", "inlinedResponses"),
      payload.dig("dest", "inlinedResponses"),
      payload.dig("response", "dest", "inlinedResponses")
    ].compact

    candidates.each do |candidate|
      return candidate if candidate.is_a?(Array)
      return candidate["inlinedResponses"] if candidate.is_a?(Hash) && candidate["inlinedResponses"].is_a?(Array)
    end

    []
  end

  # The Gemini Batch API on generativelanguage.googleapis.com uses BATCH_STATE_*
  # values; the Vertex AI batch flow (and some doc snippets) uses JOB_STATE_*.
  # Match both since hosts may flip between endpoints.
  def map_job_state(state)
    case state
    when "BATCH_STATE_PENDING", "BATCH_STATE_QUEUED",
         "JOB_STATE_PENDING", "JOB_STATE_QUEUED" then "in_progress"
    when "BATCH_STATE_RUNNING", "BATCH_STATE_PROCESSING", "BATCH_STATE_CANCELLING",
         "JOB_STATE_RUNNING", "JOB_STATE_PROCESSING", "JOB_STATE_CANCELLING" then "in_progress"
    when "BATCH_STATE_SUCCEEDED", "JOB_STATE_SUCCEEDED" then "ended"
    when "BATCH_STATE_FAILED", "JOB_STATE_FAILED" then "failed"
    when "BATCH_STATE_CANCELLED", "JOB_STATE_CANCELLED" then "canceled"
    when "BATCH_STATE_EXPIRED", "JOB_STATE_EXPIRED" then "expired"
    when nil then nil
    else
      Raif.logger.warn(
        "Raif::Concerns::Llms::Google::BatchInference: unknown Gemini batch state " \
          "#{state.inspect}; treating as in_progress. The provider may have introduced a new " \
          "state that Raif doesn't yet recognize."
      )
      "in_progress"
    end
  end
end
