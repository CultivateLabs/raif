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

  has_one :raif_model_response, as: :source, dependent: :destroy, class_name: "Raif::ModelResponse"

  delegate :available_model_tools, to: :raif_conversation

  accepts_nested_attributes_for :raif_user_tool_invocation

  boolean_timestamp :started_at
  boolean_timestamp :completed_at
  boolean_timestamp :failed_at

  before_validation :add_user_tool_invocation_to_user_message, on: :create

  def add_user_tool_invocation_to_user_message
    return unless raif_user_tool_invocation.present?

    self.user_message = <<~MESSAGE.strip
      #{raif_user_tool_invocation.as_user_message}

      #{user_message}
    MESSAGE
  end

  def generating_response?
    started? && !completed? && !failed?
  end

  def process_entry!
    model_response = raif_conversation.prompt_model_for_entry_response(entry: self)
    self.model_raw_response = model_response.raw_response

    if model_raw_response.present?
      extract_message_and_invoke_tools!
    else
      failed!
    end

    self
  end

private

  # We expect the the model to respond with JSON like:
  # {
  #   "message": "The message to display to the user",
  #   "tool": {
  #     "name": "tool_name",
  #     "arguments": { "argument_name": "argument_value" }
  #   }
  # }
  def extract_message_and_invoke_tools!
    transaction do
      begin
        parsed_response = JSON.parse(model_raw_response)
        
        if parsed_response["message"].blank?
          failed!
          return
        end

        self.model_response_message = parsed_response["message"].strip
        save!

        if parsed_response["tool"].present?
          tool_call = parsed_response["tool"]
          tool_klass = available_model_tools_map[tool_call["name"]]
          tool_klass&.invoke_tool(tool_arguments: tool_call["arguments"], source: self)
        end

        completed!
      rescue JSON::ParserError
        failed!
        return
      end
    end
  end

end
