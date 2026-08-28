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

    it "omits retired models" do
      retired_keys = Raif.model_manifest.llm_entries.select(&:retired?).map(&:key)
      registered_keys = configs_by_adapter.values.flatten.map { |config| config[:key] }
      expect(registered_keys & retired_keys).to be_empty
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
      expected = Raif::ModelManifest::RegistryData.streaming_unsupported_keys(Raif.model_manifest)
      expect(Raif.default_streaming_unsupported_model_keys).to eq(expected)
      expect(Raif.default_streaming_unsupported_model_keys).to be_frozen
    end
  end
end
