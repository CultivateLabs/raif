# frozen_string_literal: true

require "rails_helper"
require "raif/model_manifest"

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

    it "includes retired entries (callers filter on status)" do
      retired = manifest.llm_entries.select(&:retired?)
      expect(retired.map(&:key)).to eq([:open_ai_gpt_gone])
    end

    it "maps providers to adapter class names" do
      entry = manifest.llm_entries.find { |e| e.key == :anthropic_test_model }
      expect(entry.adapter_class_name).to eq("Raif::Llms::Anthropic")

      responses = manifest.llm_entries.find { |e| e.key == :open_ai_responses_gpt_test }
      expect(responses.adapter_class_name).to eq("Raif::Llms::OpenAiResponses")
      expect(responses.endpoint).to eq("responses")
      expect(responses.capabilities["pdfs"]).to eq(true)
      expect(responses.capabilities["provider_managed_tools"]).to eq(["web_search", "code_execution", "image_generation"])
    end

    it "carries pricing, display_name, max_completion_tokens, and lifecycle through" do
      entry = manifest.llm_entries.find { |e| e.key == :anthropic_test_model }
      expect(entry.pricing["input_per_million"]).to eq(3.0)
      expect(entry.display_name).to eq("Anthropic Test Model")
      expect(entry.max_completion_tokens).to eq(64000)
      expect(entry.lifecycle["status"]).to eq("active")
    end

    it "flags deprecated entries" do
      entry = manifest.llm_entries.find { |e| e.key == :anthropic_old_model }
      expect(entry).to be_deprecated
      expect(entry.lifecycle["replacement_key"]).to eq("anthropic_test_model")
    end
  end

  describe "Entry#unverified_capabilities" do
    it "returns capabilities with no verification record" do
      entry = manifest.llm_entries.find { |e| e.key == :anthropic_test_model }
      unverified = entry.unverified_capabilities
      expect(unverified).to include("structured_outputs", "batch_inference", "images", "pdfs")
      expect(unverified).not_to include("completion", "streaming")
    end

    it "treats a claim change as unverified" do
      entry = manifest.llm_entries.find { |e| e.key == :anthropic_test_model }
      entry.verification["results"]["streaming"]["claimed"] = false
      expect(entry.unverified_capabilities).to include("streaming")
    end

    it "treats everything as unverified when verification is null" do
      entry = manifest.llm_entries.find { |e| e.key == :anthropic_old_model }
      expect(entry.unverified_capabilities).to include("completion")
    end
  end

  describe "#embedding_entries" do
    it "loads embedding models with adapter and vector size" do
      entry = manifest.embedding_entries.find { |e| e.key == :open_ai_test_embedding }
      expect(entry.adapter_class_name).to eq("Raif::EmbeddingModels::OpenAi")
      expect(entry.default_output_vector_size).to eq(1536)
    end
  end

  describe "#references_for" do
    it "returns provider reference URLs" do
      expect(manifest.references_for("anthropic")["pricing"]).to eq("https://claude.com/pricing")
    end
  end
end
