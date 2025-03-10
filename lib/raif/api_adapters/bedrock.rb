# frozen_string_literal: true

require "aws-sdk-bedrock"
require "aws-sdk-bedrockruntime"

module Raif
  module ApiAdapters
    class Bedrock < Base

      def initialize(**args)
        args[:client] ||= Aws::BedrockRuntime::Client.new(region: Raif.config.aws_bedrock_region)
        super(**args)
      end

      def chat(messages:, response_format: :text, system_prompt: nil)
        assistant_message = messages.find { |message| message[:role] == "assistant" }
        messages = messages.map(&:symbolize_keys).map do |message|
          {
            role: message[:role],
            content: [{ text: message[:content] }]
          }
        end

        converse_params = {
          model_id: model_api_name,
          inference_config: { max_tokens: 8192 },
          messages: messages
        }
        converse_params[:system] = [{ text: system_prompt }] if system_prompt.present?

        resp = client.converse(converse_params)

        message = resp.output.message
        response_text = message.content.first.text

        # If this is a Claude model (indicated by anthropic.claude prefix) and we have an assistant message,
        # prepend it to the response
        if model_api_name.start_with?("anthropic.claude") && assistant_message
          response_text = assistant_message[:content] + response_text
        end

        Raif::ModelResponse.new(
          raw_response: response_text,
          completion_tokens: resp.usage.output_tokens,
          prompt_tokens: resp.usage.input_tokens,
          total_tokens: resp.usage.total_tokens,
        )
      end
    end
  end
end
