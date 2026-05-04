# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_model_completion_batches
#
#  id                             :bigint           not null, primary key
#  completion_handler_class_name  :string
#  creator_type                   :string
#  ended_at                       :datetime
#  failed_at                      :datetime
#  failure_error                  :string
#  failure_reason                 :text
#  llm_model_key                  :string           not null
#  metadata                       :jsonb
#  model_api_name                 :string           not null
#  next_poll_at                   :datetime
#  output_token_cost              :decimal(10, 6)
#  prompt_token_cost              :decimal(10, 6)
#  provider_batch_id              :string
#  provider_response              :jsonb
#  request_counts                 :jsonb
#  started_at                     :datetime
#  status                         :string           default("pending"), not null
#  submitted_at                   :datetime
#  total_cost                     :decimal(10, 6)
#  type                           :string           not null
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  creator_id                     :bigint
#
# Indexes
#
#  index_raif_model_completion_batches_on_creator            (creator_type,creator_id)
#  index_raif_model_completion_batches_on_next_poll_at       (next_poll_at)
#  index_raif_model_completion_batches_on_provider_batch_id  (provider_batch_id)
#  index_raif_model_completion_batches_on_status             (status)
#  index_raif_model_completion_batches_on_submitted_at       (submitted_at)
#  index_raif_model_completion_batches_on_type               (type)
#
module Raif
  class ModelCompletionBatch < Raif::ApplicationRecord
    STATUSES = %w[pending submitted in_progress ended canceled expired failed].freeze
    TERMINAL_STATUSES = %w[ended canceled expired failed].freeze

    belongs_to :creator, polymorphic: true, optional: true

    has_many :raif_model_completions,
      class_name: "Raif::ModelCompletion",
      foreign_key: :raif_model_completion_batch_id,
      inverse_of: :raif_model_completion_batch,
      dependent: :nullify

    validates :type, presence: true
    validates :llm_model_key, presence: true
    validates :model_api_name, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }

    after_initialize -> { self.metadata ||= {} }
    after_initialize -> { self.provider_response ||= {} }
    after_initialize -> { self.request_counts ||= {} }

    scope :pending, -> { where(status: "pending") }
    scope :submitted, -> { where(status: "submitted") }
    scope :in_progress, -> { where(status: "in_progress") }
    scope :ended, -> { where(status: "ended") }
    scope :failed, -> { where(status: "failed") }
    scope :terminal, -> { where(status: TERMINAL_STATUSES) }
    scope :non_terminal, -> { where.not(status: TERMINAL_STATUSES) }
    scope :due_for_poll, ->(at: Time.current) { non_terminal.where(arel_table[:next_poll_at].lteq(at)) }

    def terminal?
      TERMINAL_STATUSES.include?(status)
    end

    def successful?
      status == "ended"
    end

    def llm
      Raif.llm(llm_model_key.to_sym)
    end

    # Consumer-facing API: ask the batch to do its provider's work.
    #
    # Each method delegates to the LLM provider's SupportsBatchInference
    # implementation. The provider-side methods (Raif::Llm#submit_batch!,
    # #fetch_batch_status!, #fetch_batch_results!) are the contract every
    # batch-capable provider implements; these façades are how callers
    # actually invoke them.

    def submit!
      llm.submit_batch!(self)
    end

    def fetch_status!
      llm.fetch_batch_status!(self)
    end

    def fetch_results!
      llm.fetch_batch_results!(self)
    end

    # Resolves and invokes the batch's completion handler, if one is configured.
    # The handler class must implement `.handle_batch_completion(batch)`.
    def dispatch_completion_handler!
      return if completion_handler_class_name.blank?

      handler = completion_handler_class_name.safe_constantize
      if handler.blank?
        Raif.logger.error(
          "Raif::ModelCompletionBatch##{id} has completion_handler_class_name=#{completion_handler_class_name.inspect} " \
            "which could not be resolved to a class. Skipping handler dispatch."
        )
        return
      end

      handler.handle_batch_completion(self)
    end

    # True once submitted_at is older than Raif.config.model_completion_batch_max_age.
    # Used by the polling and expire-stuck jobs to decide when to force-fail a batch
    # that the provider hasn't finalized in time.
    def max_age_exceeded?
      return false if submitted_at.blank?

      Time.current - submitted_at >= Raif.config.model_completion_batch_max_age
    end

    # Called by the polling job once the batch reaches a terminal status. On
    # `ended` (successful), fetches per-entry results from the provider. On the
    # other terminal statuses (canceled / expired / failed), force-fails every
    # still-pending child completion since there are no per-entry results to
    # collect.
    def finalize!
      if successful?
        fetch_results!
      else
        force_fail!(reason: "Batch ended with status: #{status}")
      end
    end

    # Marks every non-terminal child completion as failed and sets the batch to
    # `failed` (preserving an already-terminal status, e.g. `canceled`). Idempotent:
    # children already completed or failed are skipped.
    def force_fail!(reason:)
      reason_str = reason.to_s.truncate(255)

      unless terminal?
        update!(status: "failed", failed_at: Time.current, failure_reason: reason_str)
      end

      raif_model_completions.each do |mc|
        mc.reload
        next if mc.completed? || mc.failed?

        mc.failure_error = "Raif::ModelCompletionBatch ##{id} #{status}"
        mc.failure_reason = reason_str
        mc.update_columns(started_at: started_at) if mc.started_at.nil? && started_at.present?
        mc.failed!
      end
    end

    # Aggregates total_cost / prompt_token_cost / output_token_cost from child completions
    # after results have been applied. Should be called by the polling job once
    # all children have been finalized.
    def recalculate_costs!
      sums = raif_model_completions.pick(
        Arel.sql("SUM(prompt_token_cost) AS prompt_sum"),
        Arel.sql("SUM(output_token_cost) AS output_sum"),
        Arel.sql("SUM(total_cost) AS total_sum")
      )
      return unless sums

      prompt_sum, output_sum, total_sum = sums
      update_columns(
        prompt_token_cost: prompt_sum,
        output_token_cost: output_sum,
        total_cost: total_sum,
        updated_at: Time.current
      )
    end
  end
end
