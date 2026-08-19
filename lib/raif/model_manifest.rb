# frozen_string_literal: true

# Loads model_manifest/*.yml into plain structs. This file is intentionally
# NOT required by lib/raif.rb: the manifest is a maintenance-time artifact
# consumed by bin/generate_llm_registry, bin/smoke, and specs. The runtime
# registry is the generated lib/raif/default_llms.rb.
require "yaml"
require "date"
require "time"

module Raif
  module ModelManifest
    MANIFEST_DIR = File.expand_path("../../model_manifest", __dir__)

    PROVIDER_ADAPTERS = {
      "anthropic" => "Raif::Llms::Anthropic",
      "bedrock" => "Raif::Llms::Bedrock",
      "open_router" => "Raif::Llms::OpenRouter",
      "x_ai" => "Raif::Llms::XAi",
      "google" => "Raif::Llms::Google"
    }.freeze

    OPEN_AI_ENDPOINT_ADAPTERS = {
      "completions" => "Raif::Llms::OpenAiCompletions",
      "responses" => "Raif::Llms::OpenAiResponses"
    }.freeze

    OPEN_AI_ENDPOINT_KEY_PREFIXES = {
      "completions" => "open_ai_",
      "responses" => "open_ai_responses_"
    }.freeze

    ADAPTER_ORDER = [
      "Raif::Llms::OpenAiCompletions",
      "Raif::Llms::OpenAiResponses",
      "Raif::Llms::Anthropic",
      "Raif::Llms::Bedrock",
      "Raif::Llms::OpenRouter",
      "Raif::Llms::XAi",
      "Raif::Llms::Google"
    ].freeze

    CAPABILITY_KEYS = %w[
      temperature structured_outputs native_tool_use streaming
      batch_inference images pdfs provider_managed_tools
    ].freeze

    LIFECYCLE_STATUSES = %w[active deprecated retired].freeze

    PROVIDER_MANAGED_TOOL_CLASSES = {
      "web_search" => "Raif::ModelTools::ProviderManaged::WebSearch",
      "code_execution" => "Raif::ModelTools::ProviderManaged::CodeExecution",
      "image_generation" => "Raif::ModelTools::ProviderManaged::ImageGeneration"
    }.freeze

    # What each adapter class assumes when model_provider_settings says
    # nothing. The generator emits a settings entry only when the manifest
    # value differs from these. Values below marked VERIFIED were confirmed in
    # Task 1 Step 1; update if the grep said otherwise.
    ADAPTER_DEFAULTS = {
      "Raif::Llms::OpenAiCompletions" => { "temperature" => true, "structured_outputs" => true, "batch_inference" => true },
      "Raif::Llms::OpenAiResponses" => { "temperature" => true, "structured_outputs" => true, "batch_inference" => true },
      "Raif::Llms::Anthropic" => { "temperature" => true, "structured_outputs" => false, "batch_inference" => true },
      "Raif::Llms::Bedrock" => { "temperature" => true, "structured_outputs" => false, "batch_inference" => false },
      "Raif::Llms::OpenRouter" => { "temperature" => true, "structured_outputs" => true, "batch_inference" => false }, # VERIFIED: does not define supports_structured_outputs, mirrors OpenAI pattern -> true
      "Raif::Llms::XAi" => { "temperature" => true, "structured_outputs" => true, "batch_inference" => true }, # VERIFIED: does not define supports_structured_outputs, mirrors OpenAI pattern -> true; includes XAi::BatchInference -> true
      "Raif::Llms::Google" => { "temperature" => true, "structured_outputs" => true, "batch_inference" => true } # VERIFIED: does not define supports_structured_outputs but uses native JSON schema -> true; includes Google::BatchInference -> true
    }.freeze

    Entry = Struct.new(
      :key, :provider_name, :endpoint, :adapter_class_name, :api_name,
      :display_name, :max_completion_tokens, :pricing, :capabilities,
      :lifecycle, :verification, :source_path, :key_base,
      keyword_init: true
    ) do
      def status = lifecycle.fetch("status")
      def active? = status == "active"
      def deprecated? = status == "deprecated"
      def retired? = status == "retired"

      # Capabilities the smoke runner would test for this entry: "completion"
      # always, plus every schema capability, plus the derived
      # streaming_tool_calls when both streaming and native tool use are claimed.
      def smokable_capabilities
        caps = ["completion"]
        caps += CAPABILITY_KEYS.reject { |c| c == "provider_managed_tools" }
        caps << "provider_managed_tools" if capabilities["provider_managed_tools"]&.any?
        caps << "streaming_tool_calls" if capabilities["streaming"] && capabilities["native_tool_use"]
        caps
      end

      def claimed_value(capability)
        case capability
        when "completion" then true
        when "streaming_tool_calls" then capabilities["streaming"] && capabilities["native_tool_use"]
        when "provider_managed_tools" then capabilities["provider_managed_tools"]
        else capabilities[capability]
        end
      end

      def unverified_capabilities(stale_after_days: nil)
        results = verification&.dig("results") || {}
        smokable_capabilities.select do |cap|
          record = results[cap]
          next true if record.nil?
          next true if record["claimed"] != claimed_value(cap)

          if stale_after_days
            checked_at = Time.parse(record["checked_at"].to_s)
            next true if checked_at < Time.now - (stale_after_days * 86_400)
          end

          false
        end
      end
    end

    EmbeddingEntry = Struct.new(
      :key, :provider_name, :adapter_class_name, :api_name, :display_name,
      :input_per_million, :default_output_vector_size, :lifecycle,
      :verification, :source_path,
      keyword_init: true
    ) do
      def status = lifecycle.fetch("status")
      def active? = status == "active"
      def deprecated? = status == "deprecated"
      def retired? = status == "retired"
    end

    class Manifest
      attr_reader :llm_entries, :embedding_entries, :provider_files

      def initialize(llm_entries:, embedding_entries:, provider_references:, provider_files:)
        @llm_entries = llm_entries
        @embedding_entries = embedding_entries
        @provider_references = provider_references
        @provider_files = provider_files
      end

      def references_for(provider_name)
        @provider_references.fetch(provider_name, {})
      end
    end

    def self.load(dir: MANIFEST_DIR)
      llm_entries = []
      provider_references = {}
      provider_files = {}

      Dir[File.join(dir, "*.yml")].sort.each do |path|
        next if File.basename(path) == "embeddings.yml"

        data = YAML.safe_load_file(path, permitted_classes: [Date], aliases: true)
        provider = data.fetch("provider")
        provider_references[provider] = data["references"] || {}
        provider_files[provider] = path

        data.fetch("models").each do |model|
          llm_entries.concat(entries_for_model(provider, model, path))
        end
      end

      Manifest.new(
        llm_entries: llm_entries,
        embedding_entries: load_embeddings(File.join(dir, "embeddings.yml")),
        provider_references: provider_references,
        provider_files: provider_files
      )
    end

    def self.entries_for_model(provider, model, path)
      if provider == "open_ai"
        model.fetch("endpoints").map do |endpoint, endpoint_data|
          build_entry(
            provider: provider,
            model: model,
            path: path,
            key: :"#{OPEN_AI_ENDPOINT_KEY_PREFIXES.fetch(endpoint)}#{model.fetch("key_base")}",
            endpoint: endpoint,
            adapter: OPEN_AI_ENDPOINT_ADAPTERS.fetch(endpoint),
            capabilities: endpoint_data.fetch("capabilities"),
            verification: endpoint_data["verification"]
          )
        end
      else
        [
          build_entry(
            provider: provider,
            model: model,
            path: path,
            key: model.fetch("key").to_sym,
            endpoint: nil,
            adapter: PROVIDER_ADAPTERS.fetch(provider),
            capabilities: model.fetch("capabilities"),
            verification: model["verification"]
          )
        ]
      end
    end
    private_class_method :entries_for_model

    def self.build_entry(provider:, model:, path:, key:, endpoint:, adapter:, capabilities:, verification:)
      Entry.new(
        key: key,
        provider_name: provider,
        endpoint: endpoint,
        adapter_class_name: adapter,
        api_name: model.fetch("api_name"),
        display_name: model.fetch("display_name"),
        max_completion_tokens: model["max_completion_tokens"],
        pricing: model.fetch("pricing"),
        capabilities: capabilities,
        lifecycle: model.fetch("lifecycle"),
        verification: verification,
        source_path: path,
        key_base: model["key_base"] || model["key"]
      )
    end
    private_class_method :build_entry

    def self.load_embeddings(path)
      return [] unless File.exist?(path)

      data = YAML.safe_load_file(path, permitted_classes: [Date], aliases: true)
      data.fetch("providers").flat_map do |provider_block|
        provider_block.fetch("models").map do |model|
          EmbeddingEntry.new(
            key: model.fetch("key").to_sym,
            provider_name: provider_block.fetch("provider"),
            adapter_class_name: provider_block.fetch("adapter"),
            api_name: model.fetch("api_name"),
            display_name: model.fetch("display_name"),
            input_per_million: model.fetch("input_per_million"),
            default_output_vector_size: model.fetch("default_output_vector_size"),
            lifecycle: model.fetch("lifecycle"),
            verification: model["verification"],
            source_path: path
          )
        end
      end
    end
    private_class_method :load_embeddings
  end
end
