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

  # Exact round-trip rather than substring inclusion: an include check can't
  # catch a stale entry left behind in the generated region (the old block
  # would still be a substring of a file that also contains the new one). Only
  # eq against the whole-file transform proves the checked-in file has no
  # leftover keys the manifest no longer declares.
  it "en.yml model name sections are current" do
    content = File.read(Raif::Engine.root.join("config/locales/en.yml"))
    expect(content).to eq(generator.locale_en(manifest, content)), hint
  end

  it "initializer template key lists are current" do
    content = File.read(Raif::Engine.root.join("lib/generators/raif/install/templates/initializer.rb"))
    expect(content).to eq(generator.initializer(manifest, content)), hint
  end

  it "setup.md key lists are current" do
    content = File.read(Raif::Engine.root.join("docs/_getting_started/setup.md"))
    expect(content).to eq(generator.setup_md(manifest, content)), hint
  end

  # Regression coverage for the exact-eq assertions above: prove the
  # whole-file transforms actually strip a stale key out of the generated
  # region rather than merely tolerating it (which is all `include` checked).
  describe "stale entries" do
    it "are removed from the en.yml model_names section" do
      current = File.read(Raif::Engine.root.join("config/locales/en.yml"))
      stale = current.sub(
        "    model_names:\n",
        "    model_names:\n      anthropic_retired_stale: Anthropic Retired Stale\n"
      )

      expect(generator.locale_en(manifest, stale)).not_to eq(stale)
      expect(generator.locale_en(manifest, stale)).not_to include("anthropic_retired_stale")
    end

    it "are removed from the initializer's generated model keys block" do
      current = File.read(Raif::Engine.root.join("lib/generators/raif/install/templates/initializer.rb"))
      stale = current.sub(
        "  # END GENERATED MODEL KEYS",
        "  #   anthropic_retired_stale\n  # END GENERATED MODEL KEYS"
      )

      expect(generator.initializer(manifest, stale)).not_to eq(stale)
      expect(generator.initializer(manifest, stale)).not_to include("anthropic_retired_stale")
    end

    it "are removed from a setup.md provider section" do
      current = File.read(Raif::Engine.root.join("docs/_getting_started/setup.md"))
      stale = current.sub(
        "<!-- END GENERATED MODEL KEYS: anthropic -->",
        "- `anthropic_retired_stale`\n<!-- END GENERATED MODEL KEYS: anthropic -->"
      )

      expect(generator.setup_md(manifest, stale)).not_to eq(stale)
      expect(generator.setup_md(manifest, stale)).not_to include("anthropic_retired_stale")
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
