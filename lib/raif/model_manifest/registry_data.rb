# frozen_string_literal: true

require "raif/model_manifest"

module Raif
  module ModelManifest
    # Builds the runtime registry data structures from manifest entries.
    # Consumed by the generator (emitting them as Ruby literals) and by specs.
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
          input_token_cost: entry.pricing.fetch("input_per_million").to_f / 1_000_000,
          output_token_cost: entry.pricing.fetch("output_per_million").to_f / 1_000_000
        }
        config[:max_completion_tokens] = entry.max_completion_tokens if entry.max_completion_tokens

        settings = provider_settings_for(entry)
        config[:model_provider_settings] = settings if settings.any?

        tools = entry.capabilities.fetch("provider_managed_tools", [])
        if tools.any?
          config[:supported_provider_managed_tools] = tools.map { |t| PROVIDER_MANAGED_TOOL_CLASSES.fetch(t).constantize }
        end

        config[:supports_native_tool_use] = false unless entry.capabilities.fetch("native_tool_use")

        if entry.deprecated?
          config[:deprecated] = true
          config[:retirement_date] = entry.lifecycle["retirement_date"]
          config[:replacement_key] = entry.lifecycle["replacement_key"]&.to_sym
          config[:migration_note] = entry.lifecycle["migration_note"]
        end

        config
      end

      def self.provider_settings_for(entry)
        caps = entry.capabilities
        defaults = ADAPTER_DEFAULTS.fetch(entry.adapter_class_name)
        settings = {}

        temperature = caps.fetch("temperature")
        settings[:supports_temperature] = temperature if temperature != defaults.fetch("temperature")

        structured_outputs = caps.fetch("structured_outputs")
        settings[:supports_structured_outputs] = structured_outputs if structured_outputs != defaults.fetch("structured_outputs")

        batch_inference = caps.fetch("batch_inference")
        settings[:supports_batch_inference] = batch_inference if batch_inference != defaults.fetch("batch_inference")

        settings
      end

      def self.embedding_configs(manifest)
        manifest.embedding_entries.reject(&:retired?).group_by(&:adapter_class_name).transform_values do |entries|
          entries.map do |entry|
            {
              key: entry.key,
              api_name: entry.api_name,
              input_token_cost: entry.input_per_million.to_f / 1_000_000,
              default_output_vector_size: entry.default_output_vector_size
            }
          end
        end
      end

      # The manifest stores open_ai display_name without a "(Responses API)"
      # suffix; re-append it here for responses endpoint entries.
      def self.model_names(manifest)
        names = manifest.llm_entries.reject(&:retired?).to_h do |e|
          name = e.display_name
          name = "#{name} (Responses API)" if e.endpoint == "responses"
          [e.key.to_s, name]
        end
        names["raif_test_llm"] = "Raif Test LLM"
        names.sort.to_h
      end

      def self.embedding_model_names(manifest)
        manifest.embedding_entries.reject(&:retired?).to_h { |e| [e.key.to_s, e.display_name] }.sort.to_h
      end

      def self.streaming_unsupported_keys(manifest)
        manifest.llm_entries.reject(&:retired?).reject { |e| e.capabilities.fetch("streaming") }.map { |e| e.key.to_s }
      end
    end
  end
end
