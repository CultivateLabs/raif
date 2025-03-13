# frozen_string_literal: true

begin
  require "factory_bot_rails"
rescue LoadError # rubocop:disable Lint/SuppressedException
end

module Raif
  class Engine < ::Rails::Engine
    isolate_namespace Raif

    # If the host app is using FactoryBot, add the factories to the host app so they can be used in host apptests
    if defined?(FactoryBotRails)
      config.factory_bot.definition_file_paths += [File.expand_path("../../../spec/factories/shared", __FILE__)]
    end

    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot
      g.factory_bot dir: "spec/factories"
    end

    config.after_initialize do
      next unless Raif.config.open_ai_models_enabled

      require "openai"

      ::OpenAI.configure do |config|
        config.access_token = Raif.config.open_ai_api_key
      end

      [
        { key: :open_ai_gpt_4o_mini, api_name: "gpt-4o-mini" },
        { key: :open_ai_gpt_4o, api_name: "gpt-4o" },
        { key: :open_ai_gpt_3_5_turbo, api_name: "gpt-3.5-turbo" }
      ].each do |llm_config|
        Raif.register_llm(model_completion_type: Raif::ModelCompletions::OpenAi, **llm_config)
      end
    end

    config.after_initialize do
      next unless Raif.config.anthropic_models_enabled

      require "anthropic"

      ::Anthropic.setup do |config|
        config.api_key = Raif.config.anthropic_api_key
      end

      [
        { key: :anthropic_claude_3_7_sonnet, api_name: "claude-3-7-sonnet-latest" },
        { key: :anthropic_claude_3_5_sonnet, api_name: "claude-3-5-sonnet-latest" },
        { key: :anthropic_claude_3_opus, api_name: "claude-3-opus-latest" },
        { key: :anthropic_claude_3_haiku, api_name: "claude-3-haiku-20240307" }
      ].each do |llm_config|
        Raif.register_llm(model_completion_type: Raif::ModelCompletions::Anthropic, **llm_config)
      end
    end

    config.after_initialize do
      next unless Raif.config.anthropic_bedrock_models_enabled

      require "aws-sdk-bedrock"
      require "aws-sdk-bedrockruntime"

      [
        { key: :bedrock_claude_3_5_sonnet, api_name: "anthropic.claude-3-5-sonnet-20240620-v1:0" },
        { key: :bedrock_claude_3_7_sonnet, api_name: "anthropic.claude-3-7-sonnet-20250219-v1:0" }
      ].each do |llm_config|
        Raif.register_llm(model_completion_type: Raif::ModelCompletions::BedrockClaude, **llm_config)
      end
    end

    config.after_initialize do
      next unless Rails.env.test?

      require "#{Raif::Engine.root}/spec/support/test_completion"
      Raif.register_llm(model_completion_type: Raif::ModelCompletions::Test, key: :raif_test_llm, api_name: "raif-test-llm")
    end

    config.after_initialize do
      Raif.config.validate!
    end

    initializer "raif.assets" do
      if Rails.application.config.respond_to?(:assets)
        Rails.application.config.assets.precompile += [
          "raif.js",
          "raif.css",
          "raif_admin.css"
        ]
      end
    end

    initializer "raif.importmap", before: "importmap" do |app|
      if Rails.application.respond_to?(:importmap)
        app.config.importmap.paths << Raif::Engine.root.join("config/importmap.rb")
      end
    end

  end
end
