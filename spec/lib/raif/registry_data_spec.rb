# frozen_string_literal: true

require "rails_helper"
require "raif/model_manifest/registry_data"

RSpec.describe Raif::ModelManifest::RegistryData do
  let(:manifest) { Raif::ModelManifest.load(dir: Raif::Engine.root.join("spec/fixtures/model_manifest").to_s) }
  let(:llm_configs) { described_class.llm_configs(manifest).values.flatten }
  let(:config_for) { ->(key) { llm_configs.find { |config| config[:key] == key } } }

  describe ".config_for" do
    it "carries the manifest display_name" do
      expect(config_for.call(:open_ai_gpt_test)[:display_name]).to eq("OpenAI GPT Test")
    end

    it "suffixes responses endpoint display names" do
      expect(config_for.call(:open_ai_responses_gpt_test)[:display_name]).to eq("OpenAI GPT Test (Responses API)")
    end

    it "carries the full lifecycle hash" do
      lifecycle = config_for.call(:open_ai_gpt_test)[:lifecycle]
      expect(lifecycle.keys).to match_array(Raif::ModelManifest::LIFECYCLE_KEYS)
      expect(lifecycle[:status]).to eq(:active)
    end

    it "carries per-million pricing with its annotations" do
      pricing = config_for.call(:open_ai_gpt_test)[:pricing]
      expect(pricing.keys).to eq(%i[input_per_million output_per_million note valid_until])
      expect(pricing[:input_per_million]).to eq(1.25)
    end

    it "converts integer pricing to a float per-token cost" do
      entry = Raif::ModelManifest::Entry.new(
        key: :integer_pricing_test_model,
        provider_name: :open_ai,
        endpoint: nil,
        adapter_class_name: "Raif::Llms::OpenAiCompletions",
        api_name: "integer-pricing-test-1",
        display_name: "Integer Pricing Test Model",
        max_completion_tokens: nil,
        pricing: { input_per_million: 3, output_per_million: 15 },
        capabilities: {
          temperature: true,
          structured_outputs: true,
          native_tool_use: true,
          streaming: true,
          batch_inference: true,
          images: false,
          pdfs: false,
          provider_managed_tools: []
        },
        lifecycle: { status: :active },
        source_path: "model_manifest/open_ai.rb",
        key_base: "integer_pricing_test_model"
      )

      expect(described_class.config_for(entry)[:input_token_cost]).to eq(3.0 / 1_000_000)
    end

    it "emits provider settings only where the manifest differs from the adapter default" do
      # open_ai_gpt_test's completions endpoint declares temperature: false against an
      # OpenAiCompletions adapter default of true, and matches the default on everything else.
      expect(config_for.call(:open_ai_gpt_test)[:model_provider_settings]).to eq(supports_temperature: false)

      # anthropic_old_model's capabilities equal the Anthropic adapter defaults on every field,
      # so no settings entry is emitted at all.
      expect(config_for.call(:anthropic_old_model)[:model_provider_settings]).to be_nil
    end

    it "omits retired entries" do
      expect(llm_configs.map { |config| config[:key] }).to_not include(:open_ai_gpt_gone)

      embedding_configs = described_class.embedding_configs(manifest).values.flatten
      expect(embedding_configs.map { |config| config[:key] }).to_not include(:open_ai_test_embedding_gone)

      expect(described_class.streaming_unsupported_keys(manifest)).to_not include("open_ai_gpt_gone")
    end

    it "carries the endpoint's declared capabilities" do
      capabilities = config_for.call(:open_ai_gpt_test)[:capabilities]
      expect(capabilities.keys).to match_array(Raif::ModelManifest::CAPABILITY_KEYS)
    end

    it "still emits the deprecation fields for deprecated entries" do
      deprecated = config_for.call(:anthropic_old_model)
      expect(deprecated[:deprecated]).to be(true)
      expect(deprecated[:lifecycle][:status]).to eq(:deprecated)
      expect(deprecated[:replacement_key]).to eq(:anthropic_test_model)
      expect(deprecated[:retirement_date]).to eq(deprecated[:lifecycle][:retirement_date])
    end
  end

  describe ".embedding_configs" do
    it "carries the manifest display_name" do
      config = described_class.embedding_configs(manifest).values.flatten.first
      expect(config[:display_name]).to eq(manifest.embedding_entries.first.display_name)
    end

    it "carries lifecycle and pricing" do
      config = described_class.embedding_configs(manifest).values.flatten.find { |c| c[:key] == :open_ai_test_embedding }
      expect(config[:lifecycle].keys).to match_array(Raif::ModelManifest::LIFECYCLE_KEYS)
      expect(config[:lifecycle][:status]).to eq(:active)
      expect(config[:pricing]).to eq({ input_per_million: 0.02 })
    end
  end
end
