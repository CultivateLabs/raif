# frozen_string_literal: true

require "rails_helper"
require "raif/model_manifest"
require "raif/model_manifest/smoke_observations"
require Raif::Engine.root.join("script/smoke/selection")
require "tmpdir"
require "json"

RSpec.describe Smoke::Selection do
  let(:fixture_dir) { Raif::Engine.root.join("spec/fixtures/model_manifest").to_s }
  let(:manifest) { Raif::ModelManifest.load(dir: fixture_dir) }
  let(:entries) { manifest.llm_entries }

  around do |example|
    Dir.mktmpdir("raif-selection-spec") do |dir|
      @observations_dir = dir
      example.run
    end
  end

  def resolve(*selectors, **kwargs)
    described_class.resolve(selectors, entries, **kwargs)
  end

  # Writes a real model_smoke_results/<provider>.json into a tmpdir and loads it back through
  # Raif::ModelManifest::SmokeObservations.load, the same JSON round trip bin/smoke --stale goes
  # through, rather than constructing SmokeObservations.new with Ruby-typed records (symbols,
  # Time objects) the JSON loader can never actually produce.
  def store_with(provider:, model_key:, capability:, claimed:, checked_at: Time.now.utc)
    payload = {
      "schema_version" => Raif::ModelManifest::SmokeObservations::SCHEMA_VERSION,
      "models" => {
        model_key.to_s => {
          capability.to_s => { "claimed" => claimed, "result" => "pass", "checked_at" => checked_at.iso8601 }
        }
      }
    }
    File.write(File.join(@observations_dir, "#{provider}.json"), JSON.pretty_generate(payload))

    Raif::ModelManifest::SmokeObservations.load(dir: @observations_dir)
  end

  def empty_observations_store
    Raif::ModelManifest::SmokeObservations.load(dir: @observations_dir)
  end

  def build_entry(key:, capabilities:)
    Raif::ModelManifest::Entry.new(
      key: key,
      provider_name: :anthropic,
      endpoint: nil,
      adapter_class_name: "Raif::Llms::Anthropic",
      api_name: "#{key}-api",
      display_name: key.to_s,
      max_completion_tokens: nil,
      pricing: { input_per_million: 1.0, output_per_million: 2.0 },
      capabilities: capabilities,
      lifecycle: { status: :active },
      source_path: "spec/fixtures/model_manifest/anthropic.rb",
      key_base: key.to_s
    )
  end

  def build_embedding_entry(key:)
    Raif::ModelManifest::EmbeddingEntry.new(
      key: key,
      provider_name: :open_ai,
      adapter_class_name: "Raif::EmbeddingModels::OpenAi",
      api_name: "#{key}-api",
      display_name: key.to_s,
      input_per_million: 0.02,
      default_output_vector_size: 1536,
      lifecycle: { status: :active },
      source_path: "spec/fixtures/model_manifest/embeddings.rb"
    )
  end

  describe ".resolve" do
    it "selects a model by its exact key and marks the selector as explicit" do
      result = resolve("anthropic_test_model")

      expect(result[:entries].map(&:key)).to eq([:anthropic_test_model])
      expect(result[:explicit_keys]).to eq(["anthropic_test_model"])
      expect(result[:unknown]).to be_empty
    end

    it "selects every model for a provider prefix without marking them explicit" do
      result = resolve("anthropic")

      expect(result[:entries].map(&:key)).to contain_exactly(:anthropic_test_model, :anthropic_old_model)
      expect(result[:explicit_keys]).to be_empty
    end

    it "matches the open_ai prefix against completions endpoints, not responses endpoints" do
      result = resolve("open_ai")

      expect(result[:entries].map(&:key)).to contain_exactly(:open_ai_gpt_test)
    end

    it "matches the open_ai_responses prefix distinctly from open_ai" do
      result = resolve("open_ai_responses")

      expect(result[:entries].map(&:key)).to contain_exactly(:open_ai_responses_gpt_test, :open_ai_responses_gpt_test_pro)
    end

    it "excludes retired entries from a provider prefix match" do
      result = resolve("open_ai")

      expect(result[:entries].map(&:key)).not_to include(:open_ai_gpt_gone)
    end

    it "excludes retired entries from ALL, matched case-insensitively" do
      result = resolve("all")

      expect(result[:entries].map(&:key)).to contain_exactly(
        :anthropic_test_model, :anthropic_old_model, :open_ai_gpt_test,
        :open_ai_responses_gpt_test, :open_ai_responses_gpt_test_pro
      )
    end

    it "reports an unrecognized selector as unknown instead of raising" do
      result = resolve("not_a_real_selector")

      expect(result[:entries]).to be_empty
      expect(result[:unknown]).to eq(["not_a_real_selector"])
    end

    it "reports a retired model's own key as unknown rather than selecting it" do
      result = resolve("open_ai_gpt_gone")

      expect(result[:entries]).to be_empty
      expect(result[:unknown]).to eq(["open_ai_gpt_gone"])
    end

    describe "--stale, via an injected Raif::ModelManifest::SmokeObservations store" do
      let(:entry) do
        build_entry(
          key: :selection_spec_test_model,
          capabilities: {
            temperature: true,
            structured_outputs: false,
            native_tool_use: false,
            streaming: false,
            batch_inference: false,
            images: false,
            pdfs: false,
            provider_managed_tools: []
          }
        )
      end

      it "selects an entry when a positively claimed recordable capability has no observation" do
        result = described_class.resolve(
          [], [entry], stale_days: 30, embedding_entries: [], observations: empty_observations_store
        )

        expect(result[:entries].map(&:key)).to include(entry.key)
      end

      it "skips an entry whose recordable capabilities are all fresh" do
        fresh_store = store_with(provider: :anthropic, model_key: entry.key, capability: :completion, claimed: true)

        result = described_class.resolve([], [entry], stale_days: 30, embedding_entries: [], observations: fresh_store)

        expect(result[:entries].map(&:key)).not_to include(entry.key)
      end

      it "never selects an entry due to a claimed-false capability lacking an observation" do
        # Every recordable capability here is claimed false (temperature is claimed true but
        # isn't recordable, so it never factors in); completion (always claimed true) has a
        # recorded observation and none of the claimed-false ones do. If an unobserved
        # claimed-false capability could trigger selection, this entry would be selected; it
        # must not be.
        fresh_store = store_with(provider: :anthropic, model_key: entry.key, capability: :completion, claimed: true)

        result = described_class.resolve([], [entry], stale_days: 30, embedding_entries: [], observations: fresh_store)

        expect(result[:entries]).to be_empty
      end

      it "selects an embedding entry on a stale :embedding observation" do
        embedding_entry = build_embedding_entry(key: :selection_spec_test_embedding)

        result = described_class.resolve(
          [], [], stale_days: 30, embedding_entries: [embedding_entry], observations: empty_observations_store
        )

        expect(result[:embedding_entries].map(&:key)).to include(embedding_entry.key)
      end

      it "skips an embedding entry whose :embedding observation is fresh" do
        embedding_entry = build_embedding_entry(key: :selection_spec_test_embedding)
        embedding_fresh_store = store_with(
          provider: :open_ai, model_key: embedding_entry.key, capability: :embedding, claimed: true
        )

        result = described_class.resolve(
          [], [], stale_days: 30, embedding_entries: [embedding_entry], observations: embedding_fresh_store
        )

        expect(result[:embedding_entries]).to be_empty
      end
    end

    it "dedupes a model matched by both a pattern and an explicit selector, while still recording it as explicit" do
      result = resolve("anthropic", "anthropic_test_model")

      expect(result[:entries].map(&:key)).to contain_exactly(:anthropic_test_model, :anthropic_old_model)
      expect(result[:explicit_keys]).to eq(["anthropic_test_model"])
    end

    it "returns embedding entries under the embeddings selector, separate from llm entries" do
      result = described_class.resolve(["embeddings"], entries, embedding_entries: manifest.embedding_entries)

      expect(result[:embedding_entries].map(&:key)).to eq([:open_ai_test_embedding])
      expect(result[:entries]).to be_empty
    end

    it "returns no embedding entries when embeddings was not selected" do
      result = resolve("anthropic")

      expect(result[:embedding_entries]).to eq([])
    end

    it "resolves an exact embedding key and marks it explicit" do
      result = described_class.resolve(["open_ai_test_embedding"], entries, embedding_entries: manifest.embedding_entries)

      expect(result[:embedding_entries].map(&:key)).to eq([:open_ai_test_embedding])
      expect(result[:entries]).to be_empty
      expect(result[:explicit_keys]).to eq(["open_ai_test_embedding"])
      expect(result[:unknown]).to be_empty
    end

    it "still reports an unrecognized selector as unknown when embedding_entries are given" do
      result = described_class.resolve(["not_a_real_selector"], entries, embedding_entries: manifest.embedding_entries)

      expect(result[:unknown]).to eq(["not_a_real_selector"])
      expect(result[:embedding_entries]).to be_empty
    end

    it "reports a retired embedding model's own key as unknown rather than selecting it" do
      result = described_class.resolve(["open_ai_test_embedding_gone"], entries, embedding_entries: manifest.embedding_entries)

      expect(result[:embedding_entries]).to be_empty
      expect(result[:unknown]).to eq(["open_ai_test_embedding_gone"])
    end
  end
end
