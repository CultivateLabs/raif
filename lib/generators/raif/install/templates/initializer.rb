# frozen_string_literal: true

Raif.configure do |config|
  # Your OpenAI API key. Defaults to ENV["OPENAI_API_KEY"]
  # config.open_ai_api_key = ENV["OPENAI_API_KEY"]

  # Whether OpenAI models are enabled. Defaults to true
  # config.open_ai_models_enabled = true

  # Your Anthropic API key. Defaults to ENV["ANTHROPIC_API_KEY"]
  # config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]

  # Whether Anthropic models are enabled. Defaults to true
  # config.anthropic_models_enabled = true

  # Whether Anthropic models via AWS Bedrock are enabled. Defaults to true
  # config.anthropic_bedrock_models_enabled = true

  # The AWS Bedrock region to use. Defaults to "us-east-1"
  # config.aws_bedrock_region = "us-east-1"

  # The default LLM model to use. Defaults to "open_ai_gpt_4o"
  # Available keys:
  #   open_ai_gpt_4o_mini
  #   open_ai_gpt_4o
  #   open_ai_gpt_3_5_turbo
  #   anthropic_claude_3_7_sonnet
  #   anthropic_claude_3_5_sonnet
  #   anthropic_claude_3_5_haiku
  #   anthropic_claude_3_opus
  #   bedrock_claude_3_5_sonnet
  #   bedrock_claude_3_7_sonnet
  #   bedrock_claude_3_5_haiku
  #   bedrock_claude_3_opus
  # config.default_llm_model_key = "open_ai_gpt_4o"

  # A lambda that returns true if the current user is authorized to access admin controllers.
  # By default it returns false, so you must implement this in your application to use the admin controllers.
  # If your application's user model has an admin? method, you could use something like this:
  # config.authorize_admin_controller_action = ->{ current_user&.admin? }

  # A lambda that returns true if the current user is authorized to access non-admin controllers.
  # By default it returns false, so you must implement this in your application to use the non-admin controllers.
  # If you wanted to allow access to all logged in users, you could use something like this:
  # config.authorize_controller_action = ->{ current_user.present? }

  # The system prompt intro for Raif::Task instances. Defaults to "You are a helpful assistant."
  # config.task_system_prompt_intro = "You are a helpful assistant."

  # The system prompt intro for Raif::Conversation instances. Defaults to "You are a helpful assistant who is collaborating with a teammate."
  # config.conversation_system_prompt_intro = "You are a helpful assistant who is collaborating with a teammate."

  # The conversation types that are available. Defaults to ["Raif::Conversation"]
  # If you want to use a custom conversation type that inherits from Raif::Conversation, you can add them here.
  # config.conversation_types = ["Raif::Conversation"]

  # The controller class for conversations. Defaults to "Raif::ConversationsController"
  # If you want to use a custom controller that inherits from Raif::ConversationsController, you can set it here.
  # config.conversations_controller = "Raif::ConversationsController"

  # The controller class for conversation entries. Defaults to "Raif::ConversationEntriesController"
  # If you want to use a custom controller that inherits from Raif::ConversationEntriesController, you can set it here.
  # config.conversation_entries_controller = "Raif::ConversationEntriesController"

  # The method to call to get the current user. Defaults to :current_user
  # config.current_user_method = :current_user

  # The superclass for Raif models. Defaults to "ApplicationRecord"
  # config.model_superclass = "ApplicationRecord"

  # The user tool types that are available. Defaults to []
  # config.user_tool_types = []

  # Whether LLM API requests are enabled. Defaults to true.
  # Use this to globally disable requests to LLM APIs.
  # config.llm_api_requests_enabled = true
end
