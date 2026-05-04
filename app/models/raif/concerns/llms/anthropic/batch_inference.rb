# frozen_string_literal: true

# Anthropic Messages Batches API support for Raif::Llms::Anthropic.
# Implements the Raif::Concerns::Llms::SupportsBatchInference contract on top
# of /v1/messages/batches and the JSONL results stream.
#
# The host LLM class is expected to provide #build_request_parameters and
# #update_model_completion -- these are reused verbatim from the synchronous
# path so prompt caching, tool definitions, and response shape carry over.
module Raif::Concerns::Llms::Anthropic::BatchInference
  extend ActiveSupport::Concern

  include Raif::Concerns::Llms::SupportsBatchInference

  def batch_class
    Raif::ModelCompletionBatches::Anthropic
  end

  # Submits all child Raif::ModelCompletion records of the batch as a single
  # Anthropic Messages Batch. Each entry's `params` body is identical to what
  # the synchronous /v1/messages endpoint would receive.
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
end
