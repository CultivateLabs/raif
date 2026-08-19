# frozen_string_literal: true

require "rails_helper"
require "raif/model_manifest"
require "raif/model_manifest/registry_data"
require Raif::Engine.root.join("spec/fixtures/registry_equivalence/default_llms_snapshot")

# Temporary migration guard: proves the manifest-generated registry data is
# equivalent to the hand-written registry before the hand-written data is
# deleted. Removed once lib/raif/default_llms.rb is generated (see plan Task 8).
RSpec.describe "registry equivalence" do
  let(:manifest) { Raif::ModelManifest.load }
  let(:generated) { Raif::ModelManifest::RegistryData.llm_configs(manifest) }
  let(:snapshot) do
    RegistryEquivalenceSnapshot.default_llms.transform_keys(&:name)
  end

  it "produces the same adapters" do
    expect(generated.keys).to match_array(snapshot.keys)
  end

  it "produces equivalent configs per adapter" do
    snapshot.each do |adapter_name, snapshot_configs|
      generated_configs = generated.fetch(adapter_name)
      expect(generated_configs.map { |c| c[:key] }).to eq(snapshot_configs.map { |c| c[:key] }),
        "key mismatch for #{adapter_name}"

      snapshot_configs.zip(generated_configs).each do |expected, actual|
        expect(actual[:api_name]).to eq(expected[:api_name])
        expect(actual[:input_token_cost]).to be_within(1e-12).of(expected[:input_token_cost])
        expect(actual[:output_token_cost]).to be_within(1e-12).of(expected[:output_token_cost])
        expect(actual[:max_completion_tokens]).to eq(expected[:max_completion_tokens])
        expect(actual.fetch(:model_provider_settings, {})).to eq(expected.fetch(:model_provider_settings, {})),
          "settings mismatch for #{expected[:key]}"
        expect(actual.fetch(:supported_provider_managed_tools, [])).to eq(expected.fetch(:supported_provider_managed_tools, [])),
          "tools mismatch for #{expected[:key]}"
      end
    end
  end

  it "produces equivalent embedding configs" do
    generated = Raif::ModelManifest::RegistryData.embedding_configs(manifest)
    RegistryEquivalenceSnapshot.default_embedding_models.transform_keys(&:name).each do |adapter_name, snapshot_configs|
      generated_configs = generated.fetch(adapter_name)
      snapshot_configs.zip(generated_configs).each do |expected, actual|
        expect(actual[:key]).to eq(expected[:key])
        expect(actual[:api_name]).to eq(expected[:api_name])
        expect(actual[:input_token_cost]).to be_within(1e-12).of(expected[:input_token_cost])
        expect(actual[:default_output_vector_size]).to eq(expected[:default_output_vector_size])
      end
    end
  end

  it "produces the exact current locale names" do
    names_snapshot = YAML.safe_load_file(
      Raif::Engine.root.join("spec/fixtures/registry_equivalence/model_names_snapshot.yml")
    )
    expect(Raif::ModelManifest::RegistryData.model_names(manifest)).to eq(names_snapshot["model_names"])
    expect(Raif::ModelManifest::RegistryData.embedding_model_names(manifest)).to eq(names_snapshot["embedding_model_names"])
  end

  it "reproduces the streaming blocklist default" do
    expect(Raif::ModelManifest::RegistryData.streaming_unsupported_keys(manifest))
      .to match_array(["bedrock_gpt_oss_120b", "bedrock_gpt_oss_20b"])
  end
end
