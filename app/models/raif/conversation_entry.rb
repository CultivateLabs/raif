# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_conversation_entries
#
#  id                     :bigint           not null, primary key
#  completed_at           :datetime
#  creator_type           :string           not null
#  failed_at              :datetime
#  model_response_message :text
#  raw_response           :text
#  started_at             :datetime
#  user_message           :text
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  creator_id             :bigint           not null
#  raif_conversation_id   :bigint           not null
#
# Indexes
#
#  index_raif_conversation_entries_on_created_at            (created_at)
#  index_raif_conversation_entries_on_creator               (creator_type,creator_id)
#  index_raif_conversation_entries_on_raif_conversation_id  (raif_conversation_id)
#
# Foreign Keys
#
#  fk_rails_...  (raif_conversation_id => raif_conversations.id)
#
class Raif::ConversationEntry < Raif::ApplicationRecord
  include Raif::Concerns::InvokesModelTools
  include Raif::Concerns::HasAvailableModelTools

  belongs_to :raif_conversation, counter_cache: true, class_name: "Raif::Conversation"
  belongs_to :creator, polymorphic: true

  has_one :raif_user_tool_invocation,
    class_name: "Raif::UserToolInvocation",
    dependent: :destroy,
    foreign_key: :raif_conversation_entry_id,
    inverse_of: :raif_conversation_entry

  has_one :raif_model_completion, as: :source, dependent: :destroy, class_name: "Raif::ModelCompletion"

  delegate :available_model_tools, to: :raif_conversation
  delegate :system_prompt, :llm_model_key, :citations, to: :raif_model_completion, allow_nil: true

  accepts_nested_attributes_for :raif_user_tool_invocation

  boolean_timestamp :started_at
  boolean_timestamp :completed_at
  boolean_timestamp :failed_at

  before_validation :add_user_tool_invocation_to_user_message, on: :create

  normalizes :model_response_message, with: ->(value) { value&.strip }
  normalizes :user_message, with: ->(value) { value&.strip }

  def add_user_tool_invocation_to_user_message
    return unless raif_user_tool_invocation.present?

    separator = response_format == "html" ? "<br>" : "\n\n"
    self.user_message = [user_message, raif_user_tool_invocation.as_user_message].join(separator)
  end

  def response_format
    raif_model_completion&.response_format.presence || raif_conversation.response_format
  end

  def generating_response?
    started? && !completed? && !failed?
  end

  def process_entry!
    self.model_response_message = ""

    self.raif_model_completion = raif_conversation.prompt_model_for_entry_response(entry: self) do |model_completion, _delta, _sse_event|
      self.raw_response = model_completion.raw_response
      self.model_response_message = raif_conversation.process_model_response_message(
        message: model_completion.parsed_response(force_reparse: true),
        entry: self
      )

      update_columns(
        model_response_message: model_response_message,
        raw_response: raw_response,
        updated_at: Time.current
      )

      broadcast_replace_to raif_conversation
    end

    if raif_model_completion.present? && (raif_model_completion.parsed_response.present? || raif_model_completion.response_tool_calls.present?)
      extract_message_and_invoke_tools!
      create_entry_for_observation! if triggers_observation_to_model?
    else
      logger.error "Error processing conversation entry ##{id}. No model response found."
      failed!
    end

    self
  end

  def triggers_observation_to_model?
    return false unless completed?

    raif_model_tool_invocations.any?(&:triggers_observation_to_model?)
  end

  def create_entry_for_observation!
    follow_up_entry = raif_conversation.entries.create!(creator: creator)
    Raif::ConversationEntryJob.perform_later(conversation_entry: follow_up_entry)
    follow_up_entry.broadcast_append_to raif_conversation, target: ActionView::RecordIdentifier.dom_id(raif_conversation, :entries)
  end

private

  def extract_message_and_invoke_tools!
    transaction do
      self.raw_response = raif_model_completion.raw_response
      self.model_response_message = raif_conversation.process_model_response_message(message: raif_model_completion.parsed_response, entry: self)
      save!

      raif_model_completion.response_tool_calls&.each do |tool_call|
        tool_klass = available_model_tools_map[tool_call["name"]]
        next if tool_klass.nil?

        tool_klass.invoke_tool(tool_arguments: tool_call["arguments"], source: self)
      end

      completed!
    end
  rescue StandardError => e
    logger.error "Error processing conversation entry ##{id}. Error: #{e.message}"
    logger.error e.backtrace.join("\n")
    failed!

    raise e
  end

end
