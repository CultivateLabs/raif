# frozen_string_literal: true

# Mixed into LLM provider classes (e.g. Raif::Llms::Anthropic, Raif::Llms::OpenAiBase)
# that can submit work to the provider's Batch API in exchange for a discounted rate.
#
# The contract is intentionally narrow: a provider implementation must know how to
# (1) submit a Raif::ModelCompletionBatch holding pending Raif::ModelCompletion children,
# (2) poll the provider for status, (3) fetch and apply per-entry results, and
# (4) name the Raif::ModelCompletionBatches subclass that should back its batches.
#
# Submission, polling, and dispatch are orchestrated by Raif::PollModelCompletionBatchJob;
# providers only need to implement the four primitives below.
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
end
