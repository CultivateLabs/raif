# frozen_string_literal: true

require "rails_helper"
require "raif/model_manifest"
require "raif/model_manifest/registry_data"
require "raif/model_manifest/generator"

RSpec.describe "generated artifacts freshness" do
  manifest = Raif::ModelManifest.load
  generator = Raif::ModelManifest::Generator
  hint = "Artifacts are stale. Run bin/generate_llm_registry and commit the result."

  it "lib/raif/default_llms.rb is current" do
    expect(File.read(Raif::Engine.root.join("lib/raif/default_llms.rb"))).to eq(generator.default_llms_rb(manifest)), hint
  end

  it "lib/raif/default_embedding_models.rb is current" do
    expect(File.read(Raif::Engine.root.join("lib/raif/default_embedding_models.rb"))).to eq(generator.default_embedding_models_rb(manifest)), hint
  end

  it "en.yml model name sections are current" do
    content = File.read(Raif::Engine.root.join("config/locales/en.yml"))
    expect(content).to include(generator.model_names_yaml_block(manifest)), hint
    expect(content).to include(generator.embedding_model_names_yaml_block(manifest)), hint
  end

  it "initializer template key lists are current" do
    content = File.read(Raif::Engine.root.join("lib/generators/raif/install/templates/initializer.rb"))
    expect(content).to include(generator.initializer_keys_block(manifest)), hint
    expect(content).to include(generator.initializer_embedding_keys_block(manifest)), hint
  end

  it "setup.md key lists are current" do
    content = File.read(Raif::Engine.root.join("docs/_getting_started/setup.md"))
    %w[open_ai open_ai_responses anthropic bedrock open_router google x_ai embeddings].each do |section|
      expect(content).to include(generator.setup_md_keys_block(manifest, section)), "#{hint} (section: #{section})"
    end
  end

  it "the loaded runtime registry matches RegistryData" do
    expected = Raif::ModelManifest::RegistryData.llm_configs(manifest)
    actual = Raif.default_llms.transform_keys(&:name)
    expect(actual.keys).to eq(expected.keys)
    actual.each do |adapter, configs|
      configs.zip(expected.fetch(adapter)).each do |a, e|
        expect(a[:key]).to eq(e[:key])
        expect(a[:input_token_cost]).to be_within(1e-12).of(e[:input_token_cost])
      end
    end
  end
end
