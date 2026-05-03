# frozen_string_literal: true

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
