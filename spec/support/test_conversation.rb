# frozen_string_literal: true

class Raif::TestConversation < Raif::Conversation

  before_create :populate_available_model_tools

  def populate_available_model_tools
    self.available_model_tools = [
      "Raif::TestModelTool",
      "Raif::ModelTools::WikipediaSearch",
    ]
  end

  def process_model_response_message(message:, entry:)
    message&.gsub("jerk", "[REDACTED]")
  end

end
