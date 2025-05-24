# frozen_string_literal: true

module Raif
  module Llms
    class TestLlm < Raif::Llm
      include Raif::Concerns::Llms::OpenAi::MessageFormatting

      attr_accessor :chat_handler

      def perform_model_completion!(model_completion)
        result = chat_handler.call(model_completion.messages, model_completion)
        model_completion.raw_response = result if result.is_a?(String)
        model_completion.completion_tokens = rand(100..2000)
        model_completion.prompt_tokens = rand(100..2000)
        model_completion.total_tokens = model_completion.completion_tokens + model_completion.prompt_tokens
        model_completion.save!

        model_completion
      end
    end
  end
end
