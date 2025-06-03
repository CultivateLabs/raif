# frozen_string_literal: true

Raif.configure do |config|
  # config.conversations_controller = "ConversationsController"
  # config.conversation_entries_controller = "ConversationEntriesController"

  config.anthropic_api_key = "placeholder"
  config.anthropic_models_enabled = true

  config.open_ai_api_key = "placeholder"
  config.open_ai_models_enabled = true
  config.open_ai_embedding_models_enabled = true

  config.open_router_api_key = "placeholder"
  config.open_router_models_enabled = true

  config.bedrock_embedding_models_enabled = true
  config.bedrock_models_enabled = true

  config.authorize_controller_action = ->() { true }
  config.authorize_admin_controller_action = ->() { true }
end
