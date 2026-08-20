# frozen_string_literal: true

require "rails_helper"
require "raif/model_manifest"
require Raif::Engine.root.join("script/smoke/checks")

RSpec.describe Smoke::Checks do
  # A fixture entry with a deliberate mix of claims, so a single run_for call can exercise every
  # dispatch rule: temperature/structured_outputs are claimed false but cheap (probed anyway);
  # batch_inference/images are claimed false and expensive (omitted unless explicitly requested);
  # native_tool_use/streaming/pdfs/provider_managed_tools are claimed true (run normally); and
  # streaming + native_tool_use both being true derives the streaming_tool_calls capability.
  let(:entry) do
    Raif::ModelManifest::Entry.new(
      key: :smoke_checks_test_model,
      provider_name: "anthropic",
      endpoint: nil,
      adapter_class_name: "Raif::Llms::Anthropic",
      api_name: "smoke-checks-test-1",
      display_name: "Smoke Checks Test Model",
      max_completion_tokens: 4096,
      pricing: { "input_per_million" => 1.0, "output_per_million" => 2.0 },
      capabilities: {
        "temperature" => false,
        "structured_outputs" => false,
        "native_tool_use" => true,
        "streaming" => true,
        "batch_inference" => false,
        "images" => false,
        "pdfs" => true,
        "provider_managed_tools" => ["web_search"]
      },
      lifecycle: { "status" => "active" },
      verification: nil,
      source_path: "spec/fixtures/model_manifest/anthropic.yml",
      key_base: "smoke_checks_test_model"
    )
  end

  # native_tool_use claimed true but streaming claimed false (e.g. a model whose streaming
  # path is disabled/broken): streaming_tool_calls is smokable but claimed false, so a full
  # run should omit it while --only streaming_tool_calls still runs it as a diagnostic.
  let(:streaming_disabled_entry) do
    Raif::ModelManifest::Entry.new(
      key: :smoke_checks_streaming_disabled_test_model,
      provider_name: "anthropic",
      endpoint: nil,
      adapter_class_name: "Raif::Llms::Anthropic",
      api_name: "smoke-checks-streaming-disabled-test-1",
      display_name: "Smoke Checks Streaming Disabled Test Model",
      max_completion_tokens: 4096,
      pricing: { "input_per_million" => 1.0, "output_per_million" => 2.0 },
      capabilities: {
        "temperature" => false,
        "structured_outputs" => false,
        "native_tool_use" => true,
        "streaming" => false,
        "batch_inference" => false,
        "images" => false,
        "pdfs" => true,
        "provider_managed_tools" => ["web_search"]
      },
      lifecycle: { "status" => "active" },
      verification: nil,
      source_path: "spec/fixtures/model_manifest/anthropic.yml",
      key_base: "smoke_checks_streaming_disabled_test_model"
    )
  end

  let(:model_completion) do
    instance_double(
      Raif::ModelCompletion,
      raw_response: "ok",
      response_tool_calls: [{ "name" => "wikipedia_search", "arguments" => { "query" => "PM of Canada" } }],
      response_format_parameter: "json_schema"
    )
  end

  let(:batch_relation) { double("raif_model_completions relation", reload: []) }

  let(:batch) do
    instance_double(Raif::ModelCompletionBatch, status: "ended", raif_model_completions: batch_relation)
  end

  let(:llm) do
    instance_double(
      Raif::Llms::Anthropic,
      chat: model_completion,
      create_batch: batch,
      build_pending_model_completion: instance_double(Raif::ModelCompletion),
      submit_batch!: batch,
      fetch_batch_status!: "ended",
      fetch_batch_results!: batch
    )
  end

  # The claimed-false direction of temperature/structured_outputs rebuilds the llm via
  # Raif.llm_config(entry.key)[:llm_class].new(...) rather than going through Raif.llm, so it
  # needs its own stub -- a lightweight class that accepts the forced model_provider_settings
  # kwargs and never makes a real request.
  let(:forced_llm_class) do
    Class.new do
      def initialize(**_kwargs); end

      def chat(**_kwargs)
        Struct.new(:raw_response, :response_format_parameter, :response_tool_calls).new("ok", "json_schema", nil)
      end
    end
  end

  before do
    allow(Raif).to receive(:llm).with(entry.key).and_return(llm)
    allow(Raif).to receive(:llm_config).with(entry.key).and_return(llm_class: forced_llm_class, model_provider_settings: {})
    allow(Raif).to receive(:llm).with(streaming_disabled_entry.key).and_return(llm)
    allow(Raif).to receive(:llm_config).with(streaming_disabled_entry.key).and_return(
      llm_class: forced_llm_class, model_provider_settings: {}
    )
  end

  describe "NONCE" do
    it "is the fixed marker text embedded in the image/pdf fixtures" do
      expect(described_class::NONCE).to eq("RAIF-SMOKE-7391")
    end
  end

  describe ".run_for" do
    it "runs every smokable capability, probing claimed-false cheap ones but omitting claimed-false expensive ones" do
      result = described_class.run_for(entry)

      expect(result.keys).to contain_exactly(
        "completion", "temperature", "structured_outputs", "native_tool_use",
        "streaming", "streaming_tool_calls", "pdfs", "provider_managed_tools"
      )
    end

    it "probes claimed-false cheap capabilities (temperature, structured_outputs) rather than omitting them" do
      result = described_class.run_for(entry)

      expect(result).to have_key("temperature")
      expect(result).to have_key("structured_outputs")
    end

    it "omits claimed-false expensive capabilities (batch_inference, images) from the result entirely" do
      result = described_class.run_for(entry)

      expect(result).not_to have_key("batch_inference")
      expect(result).not_to have_key("images")
    end

    it "restricts the run to just the capability named by only" do
      result = described_class.run_for(entry, only: "streaming")

      expect(result.keys).to eq(["streaming"])
    end

    it "restricts the run to an array of capabilities named by only" do
      result = described_class.run_for(entry, only: ["completion", "pdfs"])

      expect(result.keys).to contain_exactly("completion", "pdfs")
    end

    it "reports a skipped capability as status: :skip instead of running it" do
      result = described_class.run_for(entry, skip: ["pdfs"])

      expect(result["pdfs"]).to eq(status: :skip, detail: "skipped via --skip")
    end

    it "still runs every other capability when one is skipped" do
      result = described_class.run_for(entry, skip: ["pdfs"])

      expect(result).to have_key("completion")
      expect(result).to have_key("temperature")
    end

    it "forces a claimed-false expensive capability to run when explicitly requested via only" do
      result = described_class.run_for(entry, only: ["batch_inference"])

      expect(result.keys).to eq(["batch_inference"])
    end

    it "does not run a check for a capability the entry doesn't claim to have (only filters before dispatch)" do
      result = described_class.run_for(entry, only: ["not_a_real_capability"])

      expect(result).to be_empty
    end

    it "omits claimed-false streaming_tool_calls (native_tool_use true, streaming false) from a full run" do
      result = described_class.run_for(streaming_disabled_entry)

      expect(result).not_to have_key("streaming_tool_calls")
    end

    it "runs streaming_tool_calls when explicitly requested via only, despite streaming being claimed false" do
      result = described_class.run_for(streaming_disabled_entry, only: "streaming_tool_calls")

      expect(result.keys).to eq(["streaming_tool_calls"])
    end
  end
end
