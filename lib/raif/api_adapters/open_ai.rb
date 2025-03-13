# frozen_string_literal: true

module Raif
  module ApiAdapters
    class OpenAi < Base
      attr_accessor :temperature

      def initialize(**args)
        args[:client] ||= OpenAI::Client.new
        args[:temperature] ||= 0.7
        super(**args)
      end

      def chat(messages:, system_prompt: nil)
        messages_with_system = [{ role: "system", content: system_prompt }] + messages if system_prompt

        resp = client.chat(
          parameters: {
            model: model_api_name,
            messages: messages_with_system,
            temperature: temperature,
          }
        )

        Raif::ModelCompletion.new(
          messages: messages,
          system_prompt: system_prompt,
          raw_response: resp.dig("choices", 0, "message", "content"),
          completion_tokens: resp["usage"]["completion_tokens"],
          prompt_tokens: resp["usage"]["prompt_tokens"],
          total_tokens: resp["usage"]["total_tokens"],
        )
      end
    end
  end
end
