# frozen_string_literal: true

# Loads lib/raif/model_manifest/definitions/*.rb into plain structs. The
# definitions are the runtime registry: Raif.default_llms and
# Raif.default_embedding_models (lib/raif/default_models.rb) are built from
# them at boot, and bin/smoke and the manifest specs read the same files.
require "date"
require "raif/model_manifest/dsl"

module Raif
  module ModelManifest
    MANIFEST_DIR = File.expand_path("model_manifest/definitions", __dir__)

    # Provider and endpoint names are strings in these lookup maps even though
    # an entry's provider_name is a symbol: entries_for_model fetches by
    # provider.name.to_s.
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

    CAPABILITY_KEYS = %i[
      temperature structured_outputs native_tool_use streaming
      batch_inference images pdfs provider_managed_tools
    ].freeze

    LIFECYCLE_STATUSES = %i[active deprecated retired].freeze

    # Every entry's lifecycle carries all of these, defaulting to nil, so a
    # caller never has to ask whether a model declared them.
    LIFECYCLE_KEYS = %i[status added_on deprecated_on retirement_date replacement_key migration_note].freeze

    PROVIDER_MANAGED_TOOL_CLASSES = {
      "web_search" => "Raif::ModelTools::ProviderManaged::WebSearch",
      "code_execution" => "Raif::ModelTools::ProviderManaged::CodeExecution",
      "image_generation" => "Raif::ModelTools::ProviderManaged::ImageGeneration"
    }.freeze

    # What each adapter class assumes when model_provider_settings says
    # nothing. RegistryData.provider_settings_for emits a setting only when
    # the manifest value differs from these.
    ADAPTER_DEFAULTS = {
      "Raif::Llms::OpenAiCompletions" => { "temperature" => true, "structured_outputs" => true, "batch_inference" => true },
      "Raif::Llms::OpenAiResponses" => { "temperature" => true, "structured_outputs" => true, "batch_inference" => true },
      "Raif::Llms::Anthropic" => { "temperature" => true, "structured_outputs" => false, "batch_inference" => true },
      "Raif::Llms::Bedrock" => { "temperature" => true, "structured_outputs" => false, "batch_inference" => false },
      # Mirrors OpenAI for structured outputs
      "Raif::Llms::OpenRouter" => { "temperature" => true, "structured_outputs" => true, "batch_inference" => false },
      # Mirrors OpenAI for structured outputs; includes XAi::BatchInference
      "Raif::Llms::XAi" => { "temperature" => true, "structured_outputs" => true, "batch_inference" => true },
      # Native JSON schema support; includes Google::BatchInference
      "Raif::Llms::Google" => { "temperature" => true, "structured_outputs" => true, "batch_inference" => true }
    }.freeze

    Entry = Struct.new(
      :key, :provider_name, :endpoint, :adapter_class_name, :api_name,
      :display_name, :max_completion_tokens, :pricing, :capabilities,
      :lifecycle, :source_path, :key_base,
      keyword_init: true
    ) do
      def status = lifecycle.fetch(:status)
      def active? = status == :active
      def deprecated? = status == :deprecated
      def retired? = status == :retired

      # Capabilities the smoke runner would test for this entry: "completion"
      # always, plus every schema capability, plus the derived
      # streaming_tool_calls whenever native tool use is claimed (even if
      # streaming itself is claimed false, so --only streaming_tool_calls
      # still works as a diagnostic on a streaming-disabled model).
      #
      # Names are strings here and in claimed_value because that is what the
      # smoke CLI passes around; the capabilities they read are symbol-keyed.
      def smokable_capabilities
        caps = ["completion"]
        caps += CAPABILITY_KEYS.reject { |c| c == :provider_managed_tools }.map(&:to_s)
        caps << "provider_managed_tools" if capabilities[:provider_managed_tools]&.any?
        caps << "streaming_tool_calls" if capabilities[:native_tool_use]
        caps
      end

      def claimed_value(capability)
        case capability.to_s
        when "completion" then true
        when "streaming_tool_calls" then capabilities[:streaming] && capabilities[:native_tool_use]
        when "provider_managed_tools" then capabilities[:provider_managed_tools]
        else capabilities[capability.to_sym]
        end
      end
    end

    EmbeddingEntry = Struct.new(
      :key, :provider_name, :adapter_class_name, :api_name, :display_name,
      :input_per_million, :default_output_vector_size, :lifecycle,
      :source_path,
      keyword_init: true
    ) do
      def status = lifecycle.fetch(:status)
      def active? = status == :active
      def deprecated? = status == :deprecated
      def retired? = status == :retired
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

    # Each file is evaluated against its own Dsl::Context, so nothing a
    # manifest file declares can leak into the next file or into a later load.
    def self.load(dir: MANIFEST_DIR)
      llm_entries = []
      embedding_entries = []
      provider_references = {}
      provider_files = {}

      Dir[File.join(dir, "*.rb")].sort.each do |path|
        context = Dsl::Context.new.evaluate(File.read(path), path)

        context.providers.each do |provider|
          provider_references[provider.name] = provider.references
          provider_files[provider.name] = provider.source_path
          provider.models.each { |model| llm_entries.concat(entries_for_model(provider, model)) }
        end

        context.embedding_providers.each do |provider|
          embedding_entries.concat(embedding_entries_for(provider))
        end
      end

      Manifest.new(
        llm_entries: llm_entries,
        embedding_entries: embedding_entries,
        provider_references: provider_references,
        provider_files: provider_files
      )
    end

    # A model that declares endpoints expands to one entry per endpoint: the
    # endpoint picks the adapter and the key prefix (open_ai_ vs
    # open_ai_responses_) that go in front of the model's key_base, and carries
    # its own capabilities. Everything else is shared by all of its entries.
    def self.entries_for_model(provider, model)
      if model.endpoints
        model.endpoints.map do |endpoint, capabilities|
          build_entry(
            provider: provider,
            model: model,
            key: :"#{OPEN_AI_ENDPOINT_KEY_PREFIXES.fetch(endpoint)}#{model.key_base}",
            endpoint: endpoint,
            adapter: OPEN_AI_ENDPOINT_ADAPTERS.fetch(endpoint),
            capabilities: capabilities
          )
        end
      else
        [
          build_entry(
            provider: provider,
            model: model,
            key: model.key,
            endpoint: nil,
            adapter: PROVIDER_ADAPTERS.fetch(provider.name.to_s),
            capabilities: model.capabilities
          )
        ]
      end
    end
    private_class_method :entries_for_model

    def self.build_entry(provider:, model:, key:, endpoint:, adapter:, capabilities:)
      Entry.new(
        key: key,
        provider_name: provider.name,
        endpoint: endpoint,
        adapter_class_name: adapter,
        api_name: model.api_name,
        display_name: model.display_name,
        max_completion_tokens: model.max_completion_tokens,
        pricing: model.pricing,
        capabilities: capabilities,
        lifecycle: model.lifecycle,
        source_path: model.source_path,
        key_base: model.key_base
      )
    end
    private_class_method :build_entry

    def self.embedding_entries_for(provider)
      provider.models.map do |model|
        EmbeddingEntry.new(
          key: model.key,
          provider_name: provider.name,
          adapter_class_name: provider.adapter_class_name,
          api_name: model.api_name,
          display_name: model.display_name,
          input_per_million: model.input_per_million,
          default_output_vector_size: model.default_output_vector_size,
          lifecycle: model.lifecycle,
          source_path: model.source_path
        )
      end
    end
    private_class_method :embedding_entries_for
  end
end
