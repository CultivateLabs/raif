# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_user_tool_invocations
#
#  id                         :bigint           not null, primary key
#  tool_settings              :jsonb            not null
#  type                       :string           not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  raif_conversation_entry_id :bigint           not null
#
# Indexes
#
#  index_raif_user_tool_invocations_on_raif_conversation_entry_id  (raif_conversation_entry_id)
#
# Foreign Keys
#
#  fk_rails_...  (raif_conversation_entry_id => raif_conversation_entries.id)
#
class Raif::UserToolInvocation < Raif::ApplicationRecord
  belongs_to :raif_conversation_entry, class_name: "Raif::ConversationEntry"

  after_initialize -> { self.tool_settings ||= {} }

  delegate :tool_name, :tool_key, to: :class

  def message_input_placeholder
    I18n.t("#{self.class.name.underscore.gsub("/", ".")}.message_input_placeholder", default: nil)
  end

  def as_user_message
    # implement in subclasses
  end

  def self.tool_name
    I18n.t("#{name.underscore.gsub("/", ".")}.name")
  end

  def self.tool_key
    model_name.element
  end

  def self.tool_params
    []
  end
end
