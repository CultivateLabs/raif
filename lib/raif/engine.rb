# frozen_string_literal: true

begin
  require "factory_bot_rails"
rescue LoadError # rubocop:disable Lint/SuppressedException
end

module Raif
  class Engine < ::Rails::Engine
    isolate_namespace Raif

    initializer "raif.prompt_template_formats", before: :add_view_paths do
      # :prompt and :system_prompt are internal-only formats consumed by
      # Raif::Concerns::HasPromptTemplates. They must be in Mime::SET so
      # ActionView::LookupContext#formats= validation passes, but they should
      # not be selectable via the HTTP Accept header. Passing skip_lookup
      # keeps them out of Mime::Type::LOOKUP (the content-type → format
      # registry used by Mime::Type.parse), so an Accept header like
      # "application/x-raif-prompt" can't resolve to them.
      Mime::Type.register("application/x-raif-prompt", :prompt, [], [], true) unless Mime::Type.lookup_by_extension(:prompt)
      Mime::Type.register("application/x-raif-system-prompt", :system_prompt, [], [], true) unless Mime::Type.lookup_by_extension(:system_prompt)
    end

    # Prompt templates are plain-text LLM input, not HTML. Without this,
    # `<%= some_method %>` in a .prompt.erb / .system_prompt.erb would
    # HTML-escape the result (e.g. " => &quot;, ' => &#39;), corrupting
    # the prompt sent to the model. Rails' ERB handler skips escaping only
    # for mime types in `escape_ignore_list`, which defaults to ["text/plain"].
    initializer "raif.prompt_template_escape_ignore", after: "raif.prompt_template_formats" do
      ActiveSupport.on_load(:action_view) do
        ActionView::Template::Handlers::ERB.escape_ignore_list += [
          "application/x-raif-prompt",
          "application/x-raif-system-prompt"
        ]
      end
    end

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
      ActiveSupport.on_load(:action_view) do
        include Raif::Shared::ConversationsHelper
      end
    end

    config.after_initialize do
      next unless Raif.config.open_ai_models_enabled

      Raif.default_llms[Raif::Llms::OpenAiCompletions].each do |llm_config|
        Raif.register_llm(Raif::Llms::OpenAiCompletions, **llm_config)
      end

      Raif.default_llms[Raif::Llms::OpenAiResponses].each do |llm_config|
        Raif.register_llm(Raif::Llms::OpenAiResponses, **llm_config)
      end
    end

    config.after_initialize do
      next unless Raif.config.open_ai_embedding_models_enabled

      Raif.default_embedding_models[Raif::EmbeddingModels::OpenAi].each do |embedding_model_config|
        Raif.register_embedding_model(Raif::EmbeddingModels::OpenAi, **embedding_model_config)
      end
    end

    config.after_initialize do
      next unless Raif.config.anthropic_models_enabled

      Raif.default_llms[Raif::Llms::Anthropic].each do |llm_config|
        Raif.register_llm(Raif::Llms::Anthropic, **llm_config)
      end
    end

    config.after_initialize do
      next unless Raif.config.bedrock_models_enabled

      require "aws-sdk-bedrockruntime"

      Raif.default_llms[Raif::Llms::Bedrock].each do |llm_config|
        Raif.register_llm(Raif::Llms::Bedrock, **llm_config)
      end
    end

    config.after_initialize do
      next unless Raif.config.open_router_models_enabled

      Raif.default_llms[Raif::Llms::OpenRouter].each do |llm_config|
        Raif.register_llm(Raif::Llms::OpenRouter, **llm_config)
      end
    end

    config.after_initialize do
      next unless Raif.config.x_ai_models_enabled

      Raif.default_llms[Raif::Llms::XAi].each do |llm_config|
        Raif.register_llm(Raif::Llms::XAi, **llm_config)
      end
    end

    config.after_initialize do
      next unless Raif.config.google_models_enabled

      Raif.default_llms[Raif::Llms::Google].each do |llm_config|
        Raif.register_llm(Raif::Llms::Google, **llm_config)
      end
    end

    config.after_initialize do
      next unless Raif.config.google_embedding_models_enabled

      Raif.default_embedding_models[Raif::EmbeddingModels::Google].each do |embedding_model_config|
        Raif.register_embedding_model(Raif::EmbeddingModels::Google, **embedding_model_config)
      end
    end

    config.after_initialize do
      next unless Raif.config.bedrock_embedding_models_enabled

      require "aws-sdk-bedrockruntime"

      Raif.default_embedding_models[Raif::EmbeddingModels::Bedrock].each do |embedding_model_config|
        Raif.register_embedding_model(Raif::EmbeddingModels::Bedrock, **embedding_model_config)
      end
    end

    config.after_initialize do
      next unless Rails.env.test?

      Raif.config.conversation_types += ["Raif::TestConversation", "Raif::TestTemplateConversation"]
      Raif.config.agent_types += ["Raif::TestTemplateAgent"]

      require "#{Raif::Engine.root}/spec/support/test_llm"
      Raif.register_llm(Raif::Llms::TestLlm, key: :raif_test_llm, api_name: "raif-test-llm")

      require "#{Raif::Engine.root}/spec/support/test_embedding_model"
      Raif.register_embedding_model(
        Raif::EmbeddingModels::Test,
        key: :raif_test_embedding_model,
        api_name: "raif-test-embedding-model",
        default_output_vector_size: 1536
      )
    end

    config.after_initialize do
      Raif.config.validate!
    end

    config.after_initialize do
      # Check to see if the host app is missing any of our migrations
      # and print a warning if they are
      next unless Rails.env.development?
      next if File.basename($PROGRAM_NAME) == "rake"

      # Skip if we're running inside the engine's own dummy app
      next if Rails.root.to_s.include?("raif/spec/dummy")

      Raif::MigrationChecker.check_and_warn!
    end

    initializer "raif.assets" do
      if Rails.application.config.respond_to?(:assets)
        Rails.application.config.assets.precompile += [
          "raif.js",
          "raif.css",
          "raif_admin_sprockets.js",
          "raif_admin.css",
          "raif-logo-white.svg"
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
