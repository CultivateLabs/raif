# frozen_string_literal: true

Raif.configure do |config|
  # Your OpenAI API key. Defaults to ENV["OPENAI_API_KEY"]
  # config.open_ai_api_key = ENV["OPENAI_API_KEY"]

  # Whether OpenAI models are enabled.
  # config.open_ai_models_enabled = ENV["OPENAI_API_KEY"].present?

  # Whether OpenAI embedding models are enabled.
  # config.open_ai_embedding_models_enabled = ENV["OPENAI_API_KEY"].present?

  # Your Anthropic API key. Defaults to ENV["ANTHROPIC_API_KEY"]
  # config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]

  # Whether Anthropic models are enabled.
  # config.anthropic_models_enabled = ENV["ANTHROPIC_API_KEY"].present?

  # Whether Anthropic models via AWS Bedrock are enabled. Defaults to false
  # config.bedrock_models_enabled = false

  # The AWS Bedrock region to use. Defaults to "us-east-1"
  # config.aws_bedrock_region = "us-east-1"

  # Prefix to apply to the model name in AWS Bedrock API calls (e.g. us.anthropic.claude-3-5-haiku-20241022-v1:0)
  # config.aws_bedrock_model_name_prefix = "us"

  # Whether Titan embedding models are enabled. Defaults to false
  # config.bedrock_embedding_models_enabled = false

  # Your OpenRouter API key. Defaults to ENV["OPENROUTER_API_KEY"]
  # config.open_router_api_key = ENV["OPENROUTER_API_KEY"]

  # Whether OpenRouter models are enabled.
  # config.open_router_models_enabled = ENV["OPENROUTER_API_KEY"].present?

  # The app name to include in OpenRouter API requests headers. Optional.
  # config.open_router_app_name = "My App"

  # The site URL to include in OpenRouter API requests headers. Optional.
  # config.open_router_site_url = "https://myapp.com"

  # The default LLM model to use. Defaults to "open_ai_gpt_4o"
  # Available keys:
  #   open_ai_gpt_4_1
  #   open_ai_gpt_4_1_mini
  #   open_ai_gpt_4_1_nano
  #   open_ai_gpt_4o_mini
  #   open_ai_gpt_4o
  #   open_ai_gpt_3_5_turbo
  #   open_ai_responses_gpt_4_1
  #   open_ai_responses_gpt_4_1_mini
  #   open_ai_responses_gpt_4_1_nano
  #   open_ai_responses_gpt_4o_mini
  #   open_ai_responses_gpt_4o
  #   open_ai_gpt_3_5_turbo
  #   anthropic_claude_3_7_sonnet
  #   anthropic_claude_3_5_sonnet
  #   anthropic_claude_3_5_haiku
  #   anthropic_claude_3_opus
  #   bedrock_claude_3_5_sonnet
  #   bedrock_claude_3_7_sonnet
  #   bedrock_claude_3_5_haiku
  #   bedrock_claude_3_opus
  #   bedrock_amazon_nova_micro
  #   bedrock_amazon_nova_lite
  #   bedrock_amazon_nova_pro
  #   open_router_claude_3_7_sonnet
  #   open_router_llama_3_3_70b_instruct
  #   open_router_llama_3_1_8b_instruct
  #   open_router_gemini_2_0_flash
  #   open_router_deepseek_chat_v3
  #
  # config.default_llm_model_key = "open_ai_gpt_4o"

  # The default embedding model to use when calling Raif.generate_embedding!
  # Defaults to "open_ai_text_embedding_3_small"
  # Available keys:
  #   open_ai_text_embedding_3_small
  #   open_ai_text_embedding_3_large
  #   open_ai_text_embedding_ada_002
  #   bedrock_titan_embed_text_v2
  #
  # config.default_embedding_model_key = "open_ai_text_embedding_3_small"

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
  # Or you can use a lambda to return a dynamic system prompt intro:
  # config.task_system_prompt_intro = ->(task){ "You are a helpful assistant. Today's date is #{Date.today.strftime('%B %d, %Y')}." }

  # The system prompt intro for Raif::Conversation instances. Defaults to "You are a helpful assistant who is collaborating with a teammate."
  # config.conversation_system_prompt_intro = "You are a helpful assistant who is collaborating with a teammate."
  # Or you can use a lambda to return a dynamic system prompt intro:
  # config.conversation_system_prompt_intro = ->(conversation){ "You are a helpful assistant talking to #{conversation.creator.email}. Today's date is #{Date.today.strftime('%B %d, %Y')}." }

  # The conversation types that are available. Defaults to ["Raif::Conversation"]
  # If you want to use custom conversation types that inherits from Raif::Conversation, you can add them here.
  # config.conversation_types += ["Raif::MyConversation"]

  # The controller class for conversations. Defaults to "Raif::ConversationsController"
  # If you want to use a custom controller that inherits from Raif::ConversationsController, you can set it here.
  # config.conversations_controller = "Raif::ConversationsController"

  # The controller class for conversation entries. Defaults to "Raif::ConversationEntriesController"
  # If you want to use a custom controller that inherits from Raif::ConversationEntriesController, you can set it here.
  # config.conversation_entries_controller = "Raif::ConversationEntriesController"

  # The method to call to get the current user. Defaults to :current_user
  # config.current_user_method = :current_user

  # The agent types that are available. Defaults to Set.new(["Raif::Agents::ReActAgent", "Raif::Agents::NativeToolCallingAgent"])
  # If you want to use custom agent types that inherits from Raif::Agent, you can add them here.
  # config.agent_types += ["MyAgent"]

  # The superclass for Raif models. Defaults to "ApplicationRecord"
  # config.model_superclass = "ApplicationRecord"

  # The user tool types that are available. Defaults to []
  # config.user_tool_types = []

  # Whether LLM API requests are enabled. Defaults to true.
  # Use this to globally disable requests to LLM APIs.
  # config.llm_api_requests_enabled = true
end
