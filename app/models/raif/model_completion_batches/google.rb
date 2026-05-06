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
    # Google Gemini batch persistence. The Gemini Batch API is a long-running
    # operation: create returns a resource named "batches/{id}" whose state lives
    # at metadata.state (see Raif::Concerns::Llms::Google::BatchInference for the
    # response-shape parsing). The `provider_response` jsonb caches the most
    # recent operation envelope so we can pull inline results on the success poll
    # without another round-trip:
    #
    #   {
    #     "operation_name" => "batches/123456",
    #     "state" => "JOB_STATE_RUNNING",
    #     "done" => false,
    #     "response" => { ... last-seen response sub-tree, only populated on success ... }
    #   }
    #
    # provider_batch_id stores just the trailing id (not the full "batches/" path).
    class Google < Raif::ModelCompletionBatch
      def operation_name
        provider_response&.dig("operation_name").presence || (provider_batch_id.present? ? "batches/#{provider_batch_id}" : nil)
      end

      def latest_response_payload
        provider_response&.dig("response")
      end
    end
  end
end
