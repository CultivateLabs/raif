# frozen_string_literal: true

# Credential configuration and checks for the smoke runner, consolidating logic that used to be
# duplicated near-verbatim across script/smoke_llm_models.rb, script/smoke_embedding_models.rb, and
# the probe_*.rb scripts. Provider dispatch is keyed by Raif::ModelManifest::Entry#provider_name
# ("anthropic", "open_ai", "bedrock", "open_router", "google", "x_ai") since callers already have the
# entry, rather than re-deriving a provider from a model key regex.
#
# Only references Raif.config and Aws inside method bodies, so it loads standalone; calling the
# methods requires Raif (and, for Bedrock, the aws-sdk-bedrockruntime gem) already booted, which is
# true whenever bin/smoke has loaded the dummy/host Rails app.
module Smoke
  module Credentials
    # Enables live LLM API requests and configures every provider's Raif.config settings from
    # whatever credentials are present in the environment.
    def self.configure_raif!
      Raif.config.llm_api_requests_enabled = true

      if ENV["ANTHROPIC_API_KEY"].present?
        Raif.config.anthropic_models_enabled = true
        Raif.config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY")
      end

      if ENV["OPENAI_API_KEY"].present?
        Raif.config.open_ai_models_enabled = true
        Raif.config.open_ai_embedding_models_enabled = true
        Raif.config.open_ai_api_key = ENV.fetch("OPENAI_API_KEY")
      end

      if ENV["OPEN_ROUTER_API_KEY"].present? || ENV["OPENROUTER_API_KEY"].present?
        Raif.config.open_router_models_enabled = true
        Raif.config.open_router_api_key = ENV["OPEN_ROUTER_API_KEY"].presence || ENV["OPENROUTER_API_KEY"]
      end

      if ENV["GOOGLE_AI_API_KEY"].present? || ENV["GOOGLE_API_KEY"].present?
        Raif.config.google_models_enabled = true
        Raif.config.google_embedding_models_enabled = true
        Raif.config.google_api_key = ENV["GOOGLE_AI_API_KEY"].presence || ENV["GOOGLE_API_KEY"]
      end

      if ENV["XAI_API_KEY"].present? || ENV["X_AI_API_KEY"].present?
        Raif.config.x_ai_models_enabled = true
        Raif.config.x_ai_api_key = ENV["XAI_API_KEY"].presence || ENV["X_AI_API_KEY"]
      end

      # Avoid metadata service timeouts in local environments that do not expose IMDS.
      ENV["AWS_EC2_METADATA_DISABLED"] ||= "true"
      Raif.config.bedrock_models_enabled = true
      Raif.config.bedrock_embedding_models_enabled = true
      Raif.config.aws_bedrock_region = ENV.fetch("AWS_REGION", "us-east-1")
    end

    def self.missing_for?(provider_name)
      case provider_name.to_s
      when "anthropic"
        ENV["ANTHROPIC_API_KEY"].blank?
      when "bedrock"
        !bedrock_credentials_present?
      when "open_ai"
        ENV["OPENAI_API_KEY"].blank?
      when "open_router"
        ENV["OPEN_ROUTER_API_KEY"].blank? && ENV["OPENROUTER_API_KEY"].blank?
      when "google"
        ENV["GOOGLE_AI_API_KEY"].blank? && ENV["GOOGLE_API_KEY"].blank?
      when "x_ai"
        ENV["XAI_API_KEY"].blank? && ENV["X_AI_API_KEY"].blank?
      else
        false
      end
    end

    def self.instructions_for(provider_name)
      case provider_name.to_s
      when "anthropic"
        "Set ANTHROPIC_API_KEY."
      when "bedrock"
        "Configure AWS credentials (AWS_PROFILE, AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY, or IAM role) and set AWS_REGION."
      when "open_ai"
        "Set OPENAI_API_KEY."
      when "open_router"
        "Set OPEN_ROUTER_API_KEY (or OPENROUTER_API_KEY)."
      when "google"
        "Set GOOGLE_AI_API_KEY (or GOOGLE_API_KEY)."
      when "x_ai"
        "Set XAI_API_KEY (or X_AI_API_KEY)."
      else
        "Configure credentials for this provider."
      end
    end

    # Memoized per process: resolving the credential chain is not free, and it doesn't change mid-run.
    def self.bedrock_credentials_present?
      return @bedrock_credentials_present unless @bedrock_credentials_present.nil?

      credentials = Aws::CredentialProviderChain.new.resolve
      @bedrock_credentials_present = credentials&.set? || false
    rescue StandardError
      @bedrock_credentials_present = false
    end
  end
end
