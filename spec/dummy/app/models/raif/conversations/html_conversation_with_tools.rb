# frozen_string_literal: true

module Raif
  module Conversations
    class HtmlConversationWithTools < Raif::ApplicationConversation
      llm_response_format :html

      before_create -> { self.available_model_tools = ["Raif::ModelTools::ProviderManaged::WebSearch"] }

      def system_prompt_intro
        <<~PROMPT.strip
          You are an expert songwriter. You are given a topic and you need to write a song about it.

          Your response should be formatted using basic HTML tags such as <p>, <ul>, <ol>, <li>, <strong>, and <a>. Do not include any other tags.
        PROMPT
      end

      def initial_chat_message
        "What can I write you a song about?"
      end

      def process_model_response_message(message:, entry:)
        if response_format_html? && message.present?
          message = Raif::Utils::HtmlFragmentProcessor.process_links(message, add_target_blank: true, strip_tracking_parameters: true)
        end

        message
      end
    end
  end
end
