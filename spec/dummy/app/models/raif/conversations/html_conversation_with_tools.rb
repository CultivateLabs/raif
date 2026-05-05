# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_conversations
#
#  id                         :bigint           not null, primary key
#  available_model_tools      :jsonb            not null
#  available_user_tools       :jsonb            not null
#  conversation_entries_count :integer          default(0), not null
#  creator_type               :string           not null
#  generating_entry_response  :boolean          default(FALSE), not null
#  llm_messages_max_length    :integer
#  llm_model_key              :string           not null
#  requested_language_key     :string
#  response_format            :integer          default("text"), not null
#  source_type                :string
#  system_prompt              :text
#  type                       :string           not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  creator_id                 :bigint           not null
#  source_id                  :bigint
#
# Indexes
#
#  index_raif_conversations_on_created_at  (created_at)
#  index_raif_conversations_on_creator     (creator_type,creator_id)
#  index_raif_conversations_on_source      (source_type,source_id)
#
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
