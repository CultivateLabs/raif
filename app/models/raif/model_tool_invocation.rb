# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_model_tool_invocations
#
#  id                    :bigint           not null, primary key
#  completed_at          :datetime
#  failed_at             :datetime
#  result                :jsonb            not null
#  source_type           :string           not null
#  tool_arguments        :jsonb            not null
#  tool_type             :string           not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  provider_tool_call_id :string
#  source_id             :bigint           not null
#
# Indexes
#
#  index_raif_model_tool_invocations_on_source  (source_type,source_id)
#
class Raif::ModelToolInvocation < Raif::ApplicationRecord
  belongs_to :source, polymorphic: true

  after_initialize -> { self.tool_arguments ||= {} }
  after_initialize -> { self.result ||= {} }

  validates :tool_type, presence: true
  validate :ensure_valid_tool_argument_schema, if: -> { tool_type.present? && tool_arguments_schema.present? }

  delegate :renderable?,
    :tool_name,
    to: :tool

  # Instance-aware shims so callers (Raif::Conversation, Raif::ConversationEntry,
  # etc.) ask the invocation itself, which forwards `self` to the tool class.
  # Lets tools decide per-invocation rather than at the class level.
  def format_result_for_llm
    tool.format_result_for_llm(self)
  end

  def triggers_immediate_follow_up_turn?
    tool.triggers_immediate_follow_up_turn?(self)
  end

  boolean_timestamp :completed_at
  boolean_timestamp :failed_at

  def tool
    @tool ||= tool_type.constantize
  end

  # Routes through `tool_arguments_schema_for_source` so the invocation
  # validates against the schema the model saw when making the call. The
  # helper forwards `source:` only to tools whose `tool_arguments_schema`
  # accepts it, keeping existing overrides that predate the keyword working.
  def tool_arguments_schema
    tool.tool_arguments_schema_for_source(source)
  end

  # Returns tool call in the format expected by LLM message formatting
  # @param assistant_message [String, nil] Optional assistant message accompanying the tool call
  # @return [Hash] Hash representation for JSONB storage and LLM APIs
  def as_tool_call_message(assistant_message: nil)
    Raif::Messages::ToolCall.new(
      provider_tool_call_id: provider_tool_call_id,
      name: tool_name,
      arguments: tool_arguments,
      assistant_message: assistant_message
    ).to_h
  end

  # Returns tool result in the format expected by LLM message formatting
  # @return [Hash] Hash representation for JSONB storage and LLM APIs
  def as_tool_call_result_message(result: self.result)
    Raif::Messages::ToolCallResult.new(
      provider_tool_call_id: provider_tool_call_id,
      name: tool_name,
      result: result
    ).to_h
  end

  def to_partial_path
    "raif/model_tool_invocations/#{tool.invocation_partial_name}"
  end

  def admin_formatted_result
    admin_formatted_result_attempt[:formatted]
  end

  def admin_formatted_result_error
    admin_formatted_result_attempt[:error]
  end

  # True when admin should show the formatted result block — either we have
  # something to display or we have an error to surface. Always shows for
  # completed invocations: the formatted result is what was actually sent to
  # the model, even when the tool didn't override the default.
  def admin_formatted_result_available?
    admin_formatted_result.present? || admin_formatted_result_error.present?
  end

  def ensure_valid_tool_argument_schema
    unless JSON::Validator.validate(tool_arguments_schema, tool_arguments)
      errors.add(:tool_arguments, "does not match schema")
    end
  end

private

  # Best-effort reconstruction of the formatted result shown in admin. Uses the
  # current formatter code against persisted invocation data, so formatter
  # failures are captured for display instead of breaking the page render.
  def admin_formatted_result_attempt
    @admin_formatted_result_attempt ||= if completed?
      begin
        formatted = tool.format_result_for_llm(self)
        { formatted: formatted.presence, error: nil }
      rescue StandardError => e
        { formatted: nil, error: e.message }
      end
    else
      { formatted: nil, error: nil }
    end
  end

end
