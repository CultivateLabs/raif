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
  end

  describe ".embedding_configs" do
    it "carries the manifest display_name" do
      config = described_class.embedding_configs(manifest).values.flatten.first
      expect(config[:display_name]).to eq(manifest.embedding_entries.first.display_name)
    end
  end
end
