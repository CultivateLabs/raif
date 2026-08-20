# frozen_string_literal: true

require "rails_helper"
require "raif/model_manifest"
require Raif::Engine.root.join("script/smoke/selection")

RSpec.describe Smoke::Selection do
  let(:fixture_dir) { Raif::Engine.root.join("spec/fixtures/model_manifest").to_s }
  let(:manifest) { Raif::ModelManifest.load(dir: fixture_dir) }
  let(:entries) { manifest.llm_entries }

  def resolve(*selectors, **kwargs)
    described_class.resolve(selectors, entries, **kwargs)
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

    it "selects entries with any unverified capability when stale_days is given, with no selector needed" do
      result = described_class.resolve([], entries, stale_days: 30)

      expect(result[:entries].map(&:key)).to include(:anthropic_old_model)
      expect(result[:entries].map(&:key)).not_to include(:open_ai_gpt_gone)
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
