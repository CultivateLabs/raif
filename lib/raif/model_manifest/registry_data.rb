# frozen_string_literal: true

require "raif/model_manifest"

module Raif
  module ModelManifest
    # Builds the runtime registry data structures from manifest entries.
    # Consumed by Raif.default_llms and friends (lib/raif/default_models.rb) and by specs.
    module RegistryData
      def self.llm_configs(manifest)
        grouped = manifest.llm_entries.reject(&:retired?).group_by(&:adapter_class_name)
        ADAPTER_ORDER.each_with_object({}) do |adapter, out|
          entries = grouped[adapter] or next
          out[adapter] = entries.map { |entry| config_for(entry) }
        end
      end

      def self.config_for(entry)
        config = {
          key: entry.key,
          api_name: entry.api_name,
          display_name: display_name_for(entry),
          input_token_cost: entry.pricing.fetch(:input_per_million).to_f / 1_000_000,
          output_token_cost: entry.pricing.fetch(:output_per_million).to_f / 1_000_000
        }
        config[:max_completion_tokens] = entry.max_completion_tokens if entry.max_completion_tokens

        settings = provider_settings_for(entry)
        config[:model_provider_settings] = settings if settings.any?

        tools = entry.capabilities.fetch(:provider_managed_tools, [])
        if tools.any?
          # PROVIDER_MANAGED_TOOL_CLASSES stays string-keyed like the other
          # lookup maps in ModelManifest; tool symbols convert at the
          # lookup rather than the constant changing shape.
          config[:supported_provider_managed_tools] = tools.map { |t| PROVIDER_MANAGED_TOOL_CLASSES.fetch(t.to_s).constantize }
        end

        config[:supports_native_tool_use] = false unless entry.capabilities.fetch(:native_tool_use)

        config[:lifecycle] = entry.lifecycle
        config[:pricing] = {
          input_per_million: entry.pricing.fetch(:input_per_million),
          output_per_million: entry.pricing.fetch(:output_per_million),
          note: entry.pricing[:note],
          valid_until: entry.pricing[:valid_until]
        }.freeze
        config[:capabilities] = entry.capabilities

        if entry.deprecated?
          config[:deprecated] = true
          config[:retirement_date] = entry.lifecycle[:retirement_date]
          config[:replacement_key] = entry.lifecycle[:replacement_key]
          config[:migration_note] = entry.lifecycle[:migration_note]
        end

        config
      end

      def self.provider_settings_for(entry)
        caps = entry.capabilities
        defaults = ADAPTER_DEFAULTS.fetch(entry.adapter_class_name)
        settings = {}

        temperature = caps.fetch(:temperature)
        settings[:supports_temperature] = temperature if temperature != defaults.fetch("temperature")

        structured_outputs = caps.fetch(:structured_outputs)
        settings[:supports_structured_outputs] = structured_outputs if structured_outputs != defaults.fetch("structured_outputs")

        batch_inference = caps.fetch(:batch_inference)
        settings[:supports_batch_inference] = batch_inference if batch_inference != defaults.fetch("batch_inference")

        settings
      end

      # The manifest stores open_ai display_name without a "(Responses API)"
      # suffix; append it for responses endpoint entries so the two keys for
      # one model are distinguishable wherever names are shown.
      def self.display_name_for(entry)
        return entry.display_name unless entry.endpoint == "responses"

        "#{entry.display_name} (Responses API)"
      end

      def self.embedding_configs(manifest)
        manifest.embedding_entries.reject(&:retired?).group_by(&:adapter_class_name).transform_values do |entries|
          entries.map do |entry|
            {
              key: entry.key,
              api_name: entry.api_name,
              display_name: entry.display_name,
              input_token_cost: entry.input_per_million.to_f / 1_000_000,
              default_output_vector_size: entry.default_output_vector_size,
              lifecycle: entry.lifecycle,
              pricing: { input_per_million: entry.input_per_million }.freeze
            }
          end
        end
      end

      def self.streaming_unsupported_keys(manifest)
        manifest.llm_entries.reject(&:retired?).reject { |e| e.capabilities.fetch(:streaming) }.map { |e| e.key.to_s }
      end
    end
  end
end
