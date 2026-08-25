# frozen_string_literal: true

require "rails_helper"
require "raif/model_manifest"
require "tmpdir"

RSpec.describe Raif::ModelManifest do
  let(:fixture_dir) { Raif::Engine.root.join("spec/fixtures/model_manifest").to_s }
  let(:manifest) { described_class.load(dir: fixture_dir) }

  describe "#llm_entries" do
    it "expands open_ai models into one entry per endpoint with the endpoint prefix in the key" do
      keys = manifest.llm_entries.map(&:key)
      expect(keys).to include(:open_ai_gpt_test, :open_ai_responses_gpt_test)
      expect(keys).to include(:open_ai_responses_gpt_test_pro)
      expect(keys).not_to include(:open_ai_gpt_test_pro) # responses-only model
    end

    it "shares the model-level attributes across every endpoint entry it expands to" do
      completions = manifest.llm_entries.find { |e| e.key == :open_ai_gpt_test }
      responses = manifest.llm_entries.find { |e| e.key == :open_ai_responses_gpt_test }

      expect([completions, responses].map(&:api_name)).to eq(["gpt-test-1", "gpt-test-1"])
      expect([completions, responses].map(&:display_name)).to eq(["OpenAI GPT Test", "OpenAI GPT Test"])
      expect([completions, responses].map(&:key_base)).to eq(["gpt_test", "gpt_test"])
      expect(completions.pricing).to eq(responses.pricing)
      expect(completions.lifecycle).to eq(responses.lifecycle)
      # Capabilities are the one per-endpoint attribute.
      expect(completions.capabilities.fetch(:pdfs)).to be(false)
      expect(responses.capabilities.fetch(:pdfs)).to be(true)
    end

    it "includes retired entries (callers filter on status)" do
      retired = manifest.llm_entries.select(&:retired?)
      expect(retired.map(&:key)).to eq([:open_ai_gpt_gone])
    end

    it "maps providers to adapter class names" do
      entry = manifest.llm_entries.find { |e| e.key == :anthropic_test_model }
      expect(entry.provider_name).to eq(:anthropic)
      expect(entry.adapter_class_name).to eq("Raif::Llms::Anthropic")
      expect(entry.endpoint).to be_nil

      responses = manifest.llm_entries.find { |e| e.key == :open_ai_responses_gpt_test }
      expect(responses.provider_name).to eq(:open_ai)
      expect(responses.adapter_class_name).to eq("Raif::Llms::OpenAiResponses")
      expect(responses.endpoint).to eq("responses")
      expect(responses.capabilities.fetch(:pdfs)).to be(true)
      expect(responses.capabilities.fetch(:provider_managed_tools)).to eq(%i[web_search code_execution image_generation])
    end

    it "carries pricing, display_name, max_completion_tokens, and lifecycle through" do
      entry = manifest.llm_entries.find { |e| e.key == :anthropic_test_model }
      expect(entry.pricing.fetch(:input_per_million)).to eq(3.0)
      expect(entry.display_name).to eq("Anthropic Test Model")
      expect(entry.max_completion_tokens).to eq(64_000)
      expect(entry.lifecycle.fetch(:status)).to eq(:active)
      expect(entry.lifecycle.fetch(:added_on)).to eq(Date.new(2025, 11, 24))
      expect(entry.source_path).to eq(File.join(fixture_dir, "anthropic.rb"))
    end

    it "fills the lifecycle fields a model leaves undeclared with nil rather than omitting them" do
      entry = manifest.llm_entries.find { |e| e.key == :anthropic_test_model }
      expect(entry.lifecycle.keys).to eq(Raif::ModelManifest::LIFECYCLE_KEYS)
      expect(entry.lifecycle.fetch(:retirement_date)).to be_nil
      expect(entry.lifecycle.fetch(:replacement_key)).to be_nil
    end

    it "deeply freezes the declared data so a consumer cannot corrupt it" do
      entry = manifest.llm_entries.find { |e| e.key == :anthropic_test_model }
      expect(entry.capabilities).to be_frozen
      expect(entry.capabilities.fetch(:provider_managed_tools)).to be_frozen
      expect(entry.pricing).to be_frozen
      expect(entry.lifecycle).to be_frozen
    end

    it "flags deprecated entries" do
      entry = manifest.llm_entries.find { |e| e.key == :anthropic_old_model }
      expect(entry).to be_deprecated
      expect(entry.lifecycle.fetch(:replacement_key)).to eq(:anthropic_test_model)
    end
  end

  describe "Entry#smokable_capabilities and Entry#claimed_value for streaming_tool_calls" do
    # native_tool_use: true, streaming: false -- e.g. a model whose streaming path is broken
    # (see docs/_learn_more/streaming.md), where bin/smoke --only streaming_tool_calls should
    # still work as a diagnostic even though a full run wouldn't probe it by default.
    let(:streaming_disabled_entry) do
      Raif::ModelManifest::Entry.new(
        key: :streaming_disabled_test_model,
        provider_name: :bedrock,
        endpoint: nil,
        adapter_class_name: "Raif::Llms::Bedrock",
        api_name: "streaming-disabled-test-1",
        display_name: "Streaming Disabled Test Model",
        max_completion_tokens: nil,
        pricing: { input_per_million: 1.0, output_per_million: 2.0 },
        capabilities: {
          temperature: true,
          structured_outputs: false,
          native_tool_use: true,
          streaming: false,
          batch_inference: false,
          images: false,
          pdfs: false,
          provider_managed_tools: []
        },
        lifecycle: { status: :active },
        source_path: "model_manifest/bedrock.rb",
        key_base: "streaming_disabled_test_model"
      )
    end

    it "includes streaming_tool_calls in smokable_capabilities when native_tool_use is claimed, even with streaming false" do
      expect(streaming_disabled_entry.smokable_capabilities).to include("streaming_tool_calls")
    end

    it "reads symbol-keyed capabilities but answers to the string capability names the CLI passes" do
      expect(streaming_disabled_entry.smokable_capabilities).to all(be_a(String))
      expect(streaming_disabled_entry.claimed_value("native_tool_use")).to be(true)
      expect(streaming_disabled_entry.claimed_value("completion")).to be(true)
      expect(streaming_disabled_entry.claimed_value("provider_managed_tools")).to eq([])
    end

    it "claims streaming_tool_calls false when streaming is false, even though it's smokable" do
      expect(streaming_disabled_entry.claimed_value("streaming_tool_calls")).to eq(false)
    end

    it "exposes no verification attribute; staleness is derived from SmokeObservations, not the manifest" do
      expect(streaming_disabled_entry).not_to respond_to(:verification)
    end
  end

  describe "#embedding_entries" do
    it "loads embedding models with adapter and vector size" do
      entry = manifest.embedding_entries.find { |e| e.key == :open_ai_test_embedding }
      expect(entry.provider_name).to eq(:open_ai)
      expect(entry.adapter_class_name).to eq("Raif::EmbeddingModels::OpenAi")
      expect(entry.default_output_vector_size).to eq(1536)
      expect(entry.lifecycle.fetch(:status)).to eq(:active)
      expect(entry.lifecycle).to be_frozen
    end

    it "includes retired embedding models (callers filter on status)" do
      expect(manifest.embedding_entries.select(&:retired?).map(&:key)).to eq([:open_ai_test_embedding_gone])
    end
  end

  describe "#references_for" do
    it "returns provider reference URLs" do
      expect(manifest.references_for(:anthropic).fetch(:pricing)).to eq("https://claude.com/pricing")
    end

    it "returns an empty hash for a provider that declared none" do
      expect(manifest.references_for(:nope)).to eq({})
    end
  end

  describe "the declaration surface manifest files may use" do
    around do |example|
      Dir.mktmpdir("raif-manifest-dsl-spec") do |dir|
        @dsl_dir = dir
        example.run
      end
    end

    def load_manifest_source(source, basename: "provider_x.rb")
      File.write(File.join(@dsl_dir, basename), source)
      described_class.load(dir: @dsl_dir)
    end

    it "rejects a top-level declaration it does not define, naming the file and the declaration" do
      expect { load_manifest_source(<<~RUBY) }
        require "net/http"

        provider :provider_x do |p|
          p.model(key: :provider_x_model, api_name: "x", display_name: "X", pricing: {}, capabilities: {}, lifecycle: { status: :active })
        end
      RUBY
        .to raise_error(Raif::ModelManifest::Dsl::UnknownDeclaration, /provider_x\.rb.*`require`/m)
    end

    it "reports errors inside a manifest file against the file's real path and line" do
      expect { load_manifest_source("provider :provider_x do |p|\n  p.model(key: :nope)\nend\n") }
        .to raise_error(ArgumentError) { |error|
          expect(error.backtrace.join("\n")).to include("provider_x.rb:2")
        }
    end

    it "normalizes the enum-like values a manifest file spells as strings" do
      manifest = load_manifest_source(<<~RUBY)
        provider :anthropic do |p|
          p.model(
            key: :anthropic_string_valued_model,
            api_name: "claude-string-1",
            display_name: "Anthropic String Valued Model",
            pricing: { input_per_million: 1.0, output_per_million: 2.0 },
            capabilities: { streaming: true, provider_managed_tools: ["web_search"] },
            lifecycle: {
              status: "deprecated",
              replacement_key: "anthropic_test_model",
              retirement_date: Date.new(2026, 12, 1)
            }
          )
        end
      RUBY

      entry = manifest.llm_entries.sole
      expect(entry.status).to eq(:deprecated)
      expect(entry.lifecycle.fetch(:replacement_key)).to eq(:anthropic_test_model)
      expect(entry.capabilities.fetch(:provider_managed_tools)).to eq([:web_search])
    end

    it "keeps one file's declarations out of the next file's context" do
      File.write(File.join(@dsl_dir, "a_provider.rb"), "provider(:anthropic) { |p| p.references(pricing: \"https://a.example\") }\n")
      File.write(File.join(@dsl_dir, "b_provider.rb"), "provider(:x_ai) { |p| p.references(pricing: \"https://b.example\") }\n")

      manifest = described_class.load(dir: @dsl_dir)

      expect(manifest.references_for(:anthropic)).to eq({ pricing: "https://a.example" })
      expect(manifest.references_for(:x_ai)).to eq({ pricing: "https://b.example" })
      expect(manifest.llm_entries).to be_empty
    end
  end
end
