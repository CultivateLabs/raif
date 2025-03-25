# frozen_string_literal: true

class Raif::Conversation < Raif::ApplicationRecord
  include Raif::Concerns::HasLlm
  include Raif::Concerns::HasRequestedLanguage
  include Raif::Concerns::HasAvailableModelTools

  belongs_to :creator, polymorphic: true

  has_many :entries, class_name: "Raif::ConversationEntry", dependent: :destroy, foreign_key: :raif_conversation_id, inverse_of: :raif_conversation

  validates :type, inclusion: { in: ->{ Raif.config.conversation_types } }

  after_initialize -> { self.available_model_tools ||= [] }
  after_initialize -> { self.available_user_tools ||= [] }

  before_validation ->{ self.type ||= "Raif::Conversation" }, on: :create
  before_validation -> { self.system_prompt ||= build_system_prompt }, on: :create

  def build_system_prompt
    <<~PROMPT
      #{system_prompt_intro}
      #{system_prompt_language_preference}
    PROMPT
  end

  def system_prompt_intro
    Raif.config.conversation_system_prompt_intro
  end

  # i18n-tasks-use t('raif.conversation.initial_chat_message')
  def initial_chat_message
    I18n.t("#{self.class.name.underscore.gsub("/", ".")}.initial_chat_message")
  end

  def prompt_model_for_entry_response(entry:)
    llm.chat(
      messages: llm_messages,
      source: entry,
      response_format: :text,
      system_prompt: system_prompt,
      available_model_tools: available_model_tools
    )
  end

  def llm_messages
    messages = []

    entries.oldest_first.each do |entry|
      messages << { "role" => "user", "content" => entry.user_message }
      messages << { "role" => "assistant", "content" => entry.model_response_message } if entry.completed?
    end

    messages
  end

  def available_user_tool_classes
    available_user_tools.map(&:constantize)
  end

end
