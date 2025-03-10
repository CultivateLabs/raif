# frozen_string_literal: true

class Raif::Conversation < Raif::ApplicationRecord
  include Raif::Concerns::HasLlm
  include Raif::Concerns::HasRequestedLanguage

  belongs_to :creator, polymorphic: true

  has_many :entries, class_name: "Raif::ConversationEntry", dependent: :destroy, foreign_key: :raif_conversation_id, inverse_of: :raif_conversation
  has_many :raif_completions, through: :entries

  validates :type, inclusion: { in: ->{ Raif.config.conversation_types } }

  before_validation ->{ self.type ||= "Raif::Conversation" }, on: :create

  def available_model_tools
    []
  end

  # def system_prompt
  #   <<~PROMPT
  #     Your response should be a JSON object with the following format:
  #     { "message": "Your message to be displayed to the user" }
  #   PROMPT
  # end

  def system_prompt
    system_prompt = Raif.config.base_system_prompt.presence || "You are a friendly assistant."
    system_prompt += " #{system_prompt_language_preference}" if requested_language_key.present?
    system_prompt
  end

  def available_user_tools
    []
  end

  def initial_chat_message
    I18n.t("#{self.class.name.underscore.gsub("/", ".")}.initial_chat_message")
  end

  def prompt_model_for_response
    llm.chat(messages: llm_messages, system_prompt: system_prompt, response_format: :json)
  end

  def llm_messages
    messages = []

    entries.each do |entry|
      if entry.completed?
        messages << { "role" => "user", "content" => entry.full_user_message }
        messages << { "role" => "assistant", "content" => entry.model_response_message }
      else
        messages << { "role" => "user", "content" => entry.full_user_message }
      end
    end

    messages
  end

end
