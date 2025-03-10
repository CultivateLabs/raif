# frozen_string_literal: true

class Raif::ConversationEntry < Raif::ApplicationRecord
  include Raif::Concerns::InvokesModelTools

  belongs_to :raif_conversation, counter_cache: true, class_name: "Raif::Conversation"
  belongs_to :creator, polymorphic: true

  has_one :raif_user_tool_invocation,
    class_name: "Raif::UserToolInvocation",
    dependent: :destroy,
    foreign_key: :raif_conversation_entry_id,
    inverse_of: :raif_conversation_entry

  delegate :available_model_tools, to: :raif_conversation

  accepts_nested_attributes_for :raif_user_tool_invocation

  boolean_timestamp :started_at
  boolean_timestamp :completed_at
  boolean_timestamp :failed_at

  def full_user_message
    if raif_user_tool_invocation.present?
      <<~MESSAGE
        #{raif_user_tool_invocation.as_user_message}

        #{user_message}
      MESSAGE
    else
      user_message
    end.strip
  end

  def generating_response?
    started? && !completed? && !failed?
  end

  def process_entry!
    model_response = conversation.prompt_model_for_response
    self.model_raw_response = model_response.raw_response

    if model_raw_response.present?
      extract_message_and_invoke_tools
    else
      failed!
    end

    self
  end

private

  # We expect the the model to respond with something like (tool being optional):
  # <message>The message to display to the user</message>
  # <tool>{ "name": "tool_name", "arguments": { "argument_name": "argument_value" } }</tool>
  def extract_message_and_invoke_tools
    transaction do
      self.model_response_message = model_raw_response.match(%r{<message>(.*?)</message>}m)[1].strip
      self.completed_at = Time.current
      save!

      model_raw_response.match(%r{<tool>(.*?)</tool>}m).each do |action|
        tool_call = JSON.parse(action)
        tool_klass = available_model_tools_map[tool_call["name"]]
        next unless tool_klass

        tool_klass.invoke_tool(tool_arguments: tool_call["arguments"], source: self)
      rescue JSON::ParserError
        logger.error("Invalid tool response: #{action}")
      end
    end
  end

end
