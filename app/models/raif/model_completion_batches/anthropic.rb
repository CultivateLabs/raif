# frozen_string_literal: true

module Raif
  module ModelCompletionBatches
    # Anthropic batch persistence. The `provider_response` jsonb holds Anthropic-specific
    # bookkeeping populated by `Raif::Llms::Anthropic#fetch_batch_status!`:
    #
    #   { "results_url" => "...", "cancel_url" => "..." }
    class Anthropic < Raif::ModelCompletionBatch
      def results_url
        provider_response&.dig("results_url")
      end

      def cancel_url
        provider_response&.dig("cancel_url")
      end
    end
  end
end
