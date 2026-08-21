# frozen_string_literal: true

require "rails_helper"
require "raif/model_manifest"
require Raif::Engine.root.join("script/smoke/checks")
require Raif::Engine.root.join("script/smoke/recorder")
require "tmpdir"
require "fileutils"

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

  # Minimal entry for exercising check_provider_managed_tools directly: that method only calls
  # Raif.llm(entry.key) and reads entry.capabilities["provider_managed_tools"], so the rest of
  # the Entry fields are irrelevant here.
  let(:pmt_entry) do
    Raif::ModelManifest::Entry.new(
      key: :smoke_checks_pmt_test_model,
      capabilities: { "provider_managed_tools" => ["web_search", "image_generation"] }
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
    allow(Raif).to receive(:llm).with(pmt_entry.key).and_return(llm)
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

  describe ".check_provider_managed_tools" do
    it "aggregates to :skip, naming both groups, when one tool is skipped as expensive and the rest pass" do
      result = described_class.check_provider_managed_tools(pmt_entry, only_list: nil)

      expect(result[:status]).to eq(:skip)
      expect(result[:detail]).to eq("pass: web_search; skipped: image_generation (expensive; run --only provider_managed_tools)")
    end

    it "runs image_generation, instead of skipping it, when only names provider_managed_tools alongside another capability" do
      result = described_class.check_provider_managed_tools(pmt_entry, only_list: ["completion", "provider_managed_tools"])

      expect(result[:status]).to eq(:pass)
      expect(result[:detail]).to eq("pass: web_search, image_generation")
    end

    it "does not fold a skipped tool into a passing aggregate (the bug this method's ladder fixes)" do
      result = described_class.check_provider_managed_tools(pmt_entry, only_list: nil)

      expect(result[:status]).not_to eq(:pass)
    end
  end

  describe "downstream truthfulness: Smoke::Recorder never records a skipped provider_managed_tools aggregate" do
    it "leaves provider_managed_tools unrecorded and last_full_run_at unset when the aggregate is :skip" do
      fixture_dir = Raif::Engine.root.join("spec/fixtures/model_manifest").to_s

      Dir.mktmpdir("raif-checks-recorder-spec") do |dir|
        FileUtils.cp_r(Dir.glob(File.join(fixture_dir, "*")), dir)
        recording_entry = Raif::ModelManifest.load(dir: dir).llm_entries.find { |e| e.key.to_s == "anthropic_old_model" }

        capability_results = {
          "completion" => { status: :pass, detail: "ok" },
          "provider_managed_tools" => described_class.check_provider_managed_tools(pmt_entry, only_list: nil)
        }
        ran_full_unskipped = capability_results.values.none? { |result| %i[skip timeout].include?(result[:status]) }

        Smoke::Recorder.record!(recording_entry, capability_results, ran_full_unskipped: ran_full_unskipped)

        raw = YAML.safe_load_file(File.join(dir, "anthropic.yml"), permitted_classes: [Date], aliases: true)
        node = raw.fetch("models").find { |m| m["key"] == "anthropic_old_model" }

        expect(ran_full_unskipped).to eq(false)
        expect(node["verification"]["results"]).to have_key("completion")
        expect(node["verification"]["results"]).not_to have_key("provider_managed_tools")
        expect(node["verification"]).not_to have_key("last_full_run_at")
      end
    end
  end
end
