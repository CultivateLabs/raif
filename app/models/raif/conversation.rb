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
#  llm_model_key              :string           not null
#  requested_language_key     :string
#  response_format            :integer          default("text"), not null
#  system_prompt              :text
#  type                       :string           not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  creator_id                 :bigint           not null
#
# Indexes
#
#  index_raif_conversations_on_created_at  (created_at)
#  index_raif_conversations_on_creator     (creator_type,creator_id)
#
class Raif::Conversation < Raif::ApplicationRecord
  include Raif::Concerns::HasLlm
  include Raif::Concerns::HasRequestedLanguage
  include Raif::Concerns::HasAvailableModelTools
  include Raif::Concerns::LlmResponseParsing

  belongs_to :creator, polymorphic: true

  class << self
    def before_prompt_model_for_entry_response(&block)
      @before_prompt_model_for_entry_response_blocks ||= []
      @before_prompt_model_for_entry_response_blocks << block if block
    end

    def before_prompt_model_for_entry_response_blocks
      blocks = []

      # Collect blocks from ancestors (in reverse order so parent blocks run first)
      ancestors.reverse_each do |klass|
        if klass.instance_variable_defined?(:@before_prompt_model_for_entry_response_blocks)
          blocks.concat(klass.instance_variable_get(:@before_prompt_model_for_entry_response_blocks))
        end
      end

      blocks
    end
  end

  has_many :entries, class_name: "Raif::ConversationEntry", dependent: :destroy, foreign_key: :raif_conversation_id, inverse_of: :raif_conversation

  validates :type, inclusion: { in: ->{ Raif.config.conversation_types } }

  after_initialize -> { self.available_model_tools ||= [] }
  after_initialize -> { self.available_user_tools ||= [] }

  before_validation ->{ self.type ||= "Raif::Conversation" }, on: :create

  def build_system_prompt
    <<~PROMPT.strip
      #{system_prompt_intro}
      #{system_prompt_language_preference}
    PROMPT
  end

  def system_prompt_intro
    sp = Raif.config.conversation_system_prompt_intro
    sp.respond_to?(:call) ? sp.call(self) : sp
  end

  # i18n-tasks-use t('raif.conversation.initial_chat_message')
  def initial_chat_message
    I18n.t("#{self.class.name.underscore.gsub("/", ".")}.initial_chat_message")
  end

  def initial_chat_message_partial_path
    "raif/conversations/initial_chat_message"
  end

  def prompt_model_for_entry_response(entry:, &block)
    self.class.before_prompt_model_for_entry_response_blocks.each do |callback_block|
      instance_exec(entry, &callback_block)
    end

    self.system_prompt = build_system_prompt
    save!

    llm.chat(
      messages: llm_messages,
      source: entry,
      response_format: response_format.to_sym,
      system_prompt: system_prompt,
      available_model_tools: available_model_tools,
      &block
    )
  rescue StandardError => e
    Rails.logger.error("Error processing conversation entry ##{entry.id}. #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))

    entry.failed!

    if defined?(Airbrake)
      notice = Airbrake.build_notice(e)
      notice[:context][:component] = "raif_conversation"
      notice[:context][:action] = "prompt_model_for_entry_response"

      Airbrake.notify(notice)
    end

    nil
  end

  def process_model_response_message(message:, entry:)
    # no-op by default.
    # Override in subclasses for type-specific processing of the model response message
    message
  end

  def llm_messages
    messages = []

    entries.oldest_first.includes(:raif_model_tool_invocations).each do |entry|
      messages << { "role" => "user", "content" => entry.user_message } unless entry.user_message.blank?
      next unless entry.completed?

      messages << { "role" => "assistant", "content" => entry.model_response_message } unless entry.model_response_message.blank?
      entry.raif_model_tool_invocations.each do |tool_invocation|
        messages << { "role" => "assistant", "content" => tool_invocation.as_llm_message }
        messages << { "role" => "assistant", "content" => tool_invocation.result_llm_message } if tool_invocation.result_llm_message.present?
      end
    end

    messages
  end

  def available_user_tool_classes
    available_user_tools.map(&:constantize)
  end

end
