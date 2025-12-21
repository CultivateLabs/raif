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

  delegate :tool_arguments_schema,
    :renderable?,
    :tool_name,
    :triggers_observation_to_model?,
    to: :tool

  boolean_timestamp :completed_at
  boolean_timestamp :failed_at

  def tool
    @tool ||= tool_type.constantize
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
  def as_tool_call_result_message
    Raif::Messages::ToolCallResult.new(
      provider_tool_call_id: provider_tool_call_id,
      name: tool_name,
      result: result
    ).to_h
  end

  def to_partial_path
    "raif/model_tool_invocations/#{tool.invocation_partial_name}"
  end

  def ensure_valid_tool_argument_schema
    unless JSON::Validator.validate(tool_arguments_schema, tool_arguments)
      errors.add(:tool_arguments, "does not match schema")
    end
  end

end
