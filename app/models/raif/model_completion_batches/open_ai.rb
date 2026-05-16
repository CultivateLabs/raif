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
    # OpenAI batch persistence. The OpenAI Batches API is a three-step flow:
    # upload a JSONL file, create a batch referencing it, poll, then download the
    # output file. The relevant identifiers are tracked in `provider_response`:
    #
    #   {
    #     "input_file_id" => "file_...",
    #     "output_file_id" => "file_...",
    #     "error_file_id" => "file_...",
    #     "endpoint" => "/v1/responses"
    #   }
    class OpenAi < Raif::ModelCompletionBatch
      def input_file_id
        provider_response&.dig("input_file_id")
      end

      def output_file_id
        provider_response&.dig("output_file_id")
      end

      def error_file_id
        provider_response&.dig("error_file_id")
      end

      def endpoint
        provider_response&.dig("endpoint")
      end
    end
  end
end
