# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_model_completion_batches
#
#  id                            :bigint           not null, primary key
#  completion_handler_class_name :string
#  creator_type                  :string
#  ended_at                      :datetime
#  failed_at                     :datetime
#  failure_error                 :string
#  failure_reason                :text
#  handler_dispatched_at         :datetime
#  llm_model_key                 :string           not null
#  metadata                      :jsonb
#  model_api_name                :string           not null
#  next_poll_at                  :datetime
#  output_token_cost             :decimal(10, 6)
#  prompt_token_cost             :decimal(10, 6)
#  provider_response             :jsonb
#  request_counts                :jsonb
#  started_at                    :datetime
#  status                        :string           default("pending"), not null
#  submitted_at                  :datetime
#  total_cost                    :decimal(10, 6)
#  type                          :string           not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  creator_id                    :bigint
#  provider_batch_id             :string
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
  module ModelCompletionBatches
    # xAI batch persistence. xAI's Batch API does not expose a batch-level state
    # enum -- progress is tracked through counts (num_pending, num_success,
    # num_error, num_cancelled). The most relevant xAI-side metadata is mirrored
    # into `provider_response` by Raif::Llms::XAi#fetch_batch_status!:
    #
    #   { "expires_at" => "...", "cost_breakdown" => { ... } }
    class XAi < Raif::ModelCompletionBatch
      def expires_at
        ts = provider_response&.dig("expires_at")
        return if ts.blank?

        Time.zone.parse(ts.to_s)
      rescue ArgumentError
        nil
      end

      def cost_breakdown
        provider_response&.dig("cost_breakdown")
      end
    end
  end
end
