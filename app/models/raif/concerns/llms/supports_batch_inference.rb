# frozen_string_literal: true

# Mixed into LLM provider classes (e.g. Raif::Llms::Anthropic, Raif::Llms::OpenAiBase)
# that can submit work to the provider's Batch API in exchange for a discounted rate.
#
# The contract is intentionally narrow: a provider implementation must know how to
# (1) submit a Raif::ModelCompletionBatch holding pending Raif::ModelCompletion children,
# (2) poll the provider for status, (3) fetch and apply per-entry results, and
# (4) name the Raif::ModelCompletionBatches subclass that should back its batches.
# Provider-side cancellation (#cancel_batch!) is opt-in.
#
# Submission orchestration: Raif::ModelCompletionBatch#submit! enqueues
# Raif::PollModelCompletionBatchJob automatically; the job self-reschedules
# until the batch reaches a terminal status, at which point it dispatches
# the batch's completion handler.
#
# Producers: in v1, Raif::Task is the only built-in producer for batch entries
# (via Raif::Task.build_for_batch / Raif::Task#prepare_for_batch!). The
# pipeline itself (poll, finalize, dispatch handler) is producer-agnostic.
# Other call sites that want to attach Raif::ModelCompletion records to a
# batch can call Raif::Llm#build_pending_model_completion directly with
# batch_custom_id: set to a unique-within-batch identifier; the rest of the
# pipeline does not care where the completion came from.
module Raif::Concerns::Llms::SupportsBatchInference
  extend ActiveSupport::Concern

  class_methods do
    def supports_batch_inference?
      true
    end
  end

  # The Raif::ModelCompletionBatches::* STI subclass that holds batches submitted to this provider.
  # @return [Class]
  def batch_class
    raise NotImplementedError, "#{self.class.name} must implement #batch_class"
  end

  # Convenience: creates and persists a Raif::ModelCompletionBatch sized to this
  # LLM. Saves callers from having to know the provider's batch subclass or
  # repeat the LLM model key / api_name.
  #
  # All other batch attributes (creator, completion_handler_class_name,
  # metadata, ...) are forwarded.
  #
  # @return [Raif::ModelCompletionBatch] a persisted batch in the `pending` state
  def create_batch(**attrs)
    batch_class.create!(
      llm_model_key: key.to_s,
      model_api_name: api_name,
      **attrs
    )
  end

  # Submits a Raif::ModelCompletionBatch (with its child Raif::ModelCompletion records already
  # built and persisted) to the provider's Batch API. Should populate provider_batch_id,
  # provider_response, status, and submitted_at on the batch.
  #
  # @param batch [Raif::ModelCompletionBatch]
  # @return [Raif::ModelCompletionBatch] the same batch, persisted with provider state
  def submit_batch!(batch)
    raise NotImplementedError, "#{self.class.name} must implement #submit_batch!"
  end

  # Polls the provider for the batch's current status. Should update batch.status,
  # batch.request_counts, and any provider-specific bookkeeping in provider_response.
  #
  # @param batch [Raif::ModelCompletionBatch]
  # @return [String] the new status (one of Raif::ModelCompletionBatch::STATUSES)
  def fetch_batch_status!(batch)
    raise NotImplementedError, "#{self.class.name} must implement #fetch_batch_status!"
  end

  # Streams the batch's results from the provider and applies them to each child
  # Raif::ModelCompletion via #apply_batch_result. Each child should be transitioned
  # to `completed!` or `failed!` (via record_failure!) before this method returns.
  #
  # @param batch [Raif::ModelCompletionBatch]
  # @return [void]
  def fetch_batch_results!(batch)
    raise NotImplementedError, "#{self.class.name} must implement #fetch_batch_results!"
  end

  # Applies a single per-entry batch result to its corresponding Raif::ModelCompletion.
  # Implementations should populate prompt/completion tokens and any other usage data,
  # apply the provider's batch discount to token costs, and persist the completion.
  #
  # @param model_completion [Raif::ModelCompletion]
  # @param raw_result [Hash] provider-specific per-entry result payload
  # @return [Raif::ModelCompletion]
  def apply_batch_result(model_completion, raw_result)
    raise NotImplementedError, "#{self.class.name} must implement #apply_batch_result"
  end

  # Optional. Requests cancellation of a batch from the provider.
  #
  # Cancellation is typically asynchronous: the provider acknowledges with a
  # transitional status (e.g. "canceling" / "cancelling"), and the next poll
  # picks up the final "canceled" state. Implementations should send the
  # cancel request, update batch.status from the response, and return the
  # new (possibly transitional) status.
  #
  # Implementations should refuse to cancel a batch that's already terminal
  # or that hasn't been submitted yet (no provider_batch_id) by raising
  # Raif::Errors::InvalidBatchError.
  #
  # @param batch [Raif::ModelCompletionBatch]
  # @return [String] the batch's new status (one of Raif::ModelCompletionBatch::STATUSES)
  def cancel_batch!(batch)
    raise NotImplementedError, "#{self.class.name} must implement #cancel_batch!"
  end

protected

  # Wraps a single batch-API HTTP call in Raif's standard transient-error
  # retry (Raif.config.llm_request_max_retries on
  # Raif.config.llm_request_retriable_exceptions). Adapters call this around
  # individual Faraday calls inside submit_batch! / fetch_batch_status! /
  # fetch_batch_results! / cancel_batch! so a single upstream 5xx / network
  # blip self-heals before bubbling up to the host app.
  #
  # @param operation [Symbol, String] short operation label appended to the
  #   provider name in log lines (e.g. :submit, :fetch_status, :upload_input).
  # @param batch_id [Integer, nil] surfaced in the log line for traceability.
  def with_batch_transient_retry(operation, batch_id: nil, &block)
    label = +"#{self.class.name} #{operation}"
    label << " (batch ##{batch_id})" if batch_id
    Raif::Utils::TransientRetry.call(label: label, &block)
  end
end
