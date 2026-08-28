# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Raif default models" do
  describe ".model_manifest" do
    it "loads the shipped definitions once" do
      manifest = Raif.model_manifest
      expect(manifest).to be_a(Raif::ModelManifest::Manifest)
      expect(manifest.llm_entries.map(&:key)).to include(:anthropic_claude_5_sonnet, :open_ai_gpt_4o)
      expect(Raif.model_manifest).to equal(manifest)
    end
  end

  describe ".default_llms" do
    let(:configs_by_adapter) { Raif.default_llms }

    it "is keyed by adapter class" do
      expect(configs_by_adapter.keys).to all(be_a(Class))
      expect(configs_by_adapter.keys).to include(Raif::Llms::Anthropic, Raif::Llms::OpenAiCompletions, Raif::Llms::OpenAiResponses)
    end

    it "matches RegistryData for every adapter" do
      expected = Raif::ModelManifest::RegistryData.llm_configs(Raif.model_manifest)
      expect(configs_by_adapter.transform_keys(&:name)).to eq(expected)
    end

    it "matches the golden config for open_ai_gpt_4o" do
      config = configs_by_adapter.fetch(Raif::Llms::OpenAiCompletions).find { |c| c[:key] == :open_ai_gpt_4o }

      expect(config[:api_name]).to eq("gpt-4o")
      expect(config[:display_name]).to eq("OpenAI GPT-4o")
      expect(config[:input_token_cost]).to be_within(1e-12).of(2.5 / 1_000_000)
      expect(config[:output_token_cost]).to be_within(1e-12).of(10.0 / 1_000_000)
      expect(config[:pricing]).to eq({ input_per_million: 2.5, output_per_million: 10.0, note: nil, valid_until: nil })
      expect(config[:lifecycle][:status]).to eq(:active)
      expect(config[:capabilities][:streaming]).to eq(true)
    end

    it "matches the golden config for open_ai_responses_gpt_4o" do
      config = configs_by_adapter.fetch(Raif::Llms::OpenAiResponses).find { |c| c[:key] == :open_ai_responses_gpt_4o }

      expect(config[:display_name]).to eq("OpenAI GPT-4o (Responses API)")
      expect(config[:supported_provider_managed_tools]).to include(Raif::ModelTools::ProviderManaged::WebSearch)
    end

    it "is memoized" do
      expect(Raif.default_llms).to equal(configs_by_adapter)
    end
  end

  describe ".default_embedding_models" do
    it "is keyed by adapter class and matches RegistryData" do
      expected = Raif::ModelManifest::RegistryData.embedding_configs(Raif.model_manifest)
      actual = Raif.default_embedding_models
      expect(actual.keys).to all(be_a(Class))
      expect(actual.transform_keys(&:name)).to eq(expected)
    end
  end

  describe ".default_streaming_unsupported_model_keys" do
    it "lists the keys whose manifest entry declares streaming: false" do
      expect(Raif.default_streaming_unsupported_model_keys).to eq(["bedrock_gpt_oss_120b", "bedrock_gpt_oss_20b"])
      expect(Raif.default_streaming_unsupported_model_keys).to be_frozen
    end
  end
end
