# frozen_string_literal: true

require "rails_helper"
require "raif/model_manifest"
require Raif::Engine.root.join("script/smoke/recorder")
require "tmpdir"
require "fileutils"

RSpec.describe Smoke::Recorder do
  let(:fixture_dir) { Raif::Engine.root.join("spec/fixtures/model_manifest").to_s }

  around do |example|
    Dir.mktmpdir("raif-recorder-spec") do |dir|
      FileUtils.cp_r(Dir.glob(File.join(fixture_dir, "*")), dir)
      @tmp_dir = dir
      example.run
    end
  end

  def manifest
    Raif::ModelManifest.load(dir: @tmp_dir)
  end

  def entry_for(key)
    manifest.llm_entries.find { |e| e.key.to_s == key.to_s }
  end

  def open_ai_entry_for(key_base, endpoint)
    manifest.llm_entries.find { |e| e.key_base.to_s == key_base.to_s && e.endpoint == endpoint }
  end

  def raw_yaml
    YAML.safe_load_file(File.join(@tmp_dir, "anthropic.yml"), permitted_classes: [Date], aliases: true)
  end

  def raw_open_ai_yaml
    YAML.safe_load_file(File.join(@tmp_dir, "open_ai.yml"), permitted_classes: [Date], aliases: true)
  end

  def capability_result(status, detail: "detail")
    { status: status, detail: detail }
  end

  describe ".record!" do
    it "writes claimed/result/checked_at for a plain provider entry with no prior verification" do
      entry = entry_for(:anthropic_old_model)
      now = Time.utc(2026, 8, 19, 12, 0, 0)

      described_class.record!(entry, { "completion" => capability_result(:pass) }, ran_full_unskipped: false, now: now)

      node = raw_yaml.fetch("models").find { |m| m["key"] == "anthropic_old_model" }
      expect(node["verification"]["results"]["completion"]).to eq(
        "claimed" => true,
        "result" => "pass",
        "checked_at" => now.iso8601
      )
    end

    it "maps every result status to its result string, and never writes skip/timeout" do
      entry = entry_for(:anthropic_old_model)
      now = Time.utc(2026, 8, 19, 12, 0, 0)

      results = {
        "completion" => capability_result(:pass),
        "structured_outputs" => capability_result(:pass, detail: "native"),
        "native_tool_use" => capability_result(:fail, detail: "boom"),
        "temperature" => capability_result(:note, detail: "claimed unsupported but appears to work"),
        "streaming" => capability_result(:skip, detail: "skipped via --skip"),
        "batch_inference" => capability_result(:timeout, detail: "still running")
      }

      described_class.record!(entry, results, ran_full_unskipped: false, now: now)

      node = raw_yaml.fetch("models").find { |m| m["key"] == "anthropic_old_model" }
      recorded = node["verification"]["results"]

      expect(recorded.keys).to contain_exactly("completion", "structured_outputs", "native_tool_use", "temperature")
      expect(recorded["completion"]["result"]).to eq("pass")
      expect(recorded["structured_outputs"]["result"]).to eq("pass_native")
      expect(recorded["native_tool_use"]["result"]).to eq("fail")
      expect(recorded["temperature"]["result"]).to eq("note_works_despite_claim")
    end

    it "only maps pass_native/pass_json_tool for structured_outputs, not other capabilities" do
      entry = entry_for(:anthropic_old_model)

      described_class.record!(
        entry,
        {
          "structured_outputs" => capability_result(:pass, detail: "json_response_tool"),
          "images" => capability_result(:pass, detail: "native")
        },
        ran_full_unskipped: false
      )

      node = raw_yaml.fetch("models").find { |m| m["key"] == "anthropic_old_model" }
      recorded = node["verification"]["results"]

      expect(recorded["structured_outputs"]["result"]).to eq("pass_json_tool")
      expect(recorded["images"]["result"]).to eq("pass")
    end

    it "merges into existing verification results without clobbering sibling capabilities" do
      entry = entry_for(:anthropic_test_model)
      now = Time.utc(2026, 8, 19, 12, 0, 0)

      described_class.record!(entry, { "native_tool_use" => capability_result(:pass) }, ran_full_unskipped: false, now: now)

      node = raw_yaml.fetch("models").find { |m| m["key"] == "anthropic_test_model" }
      recorded = node["verification"]["results"]

      expect(recorded["completion"]).to eq("claimed" => true, "result" => "pass", "checked_at" => "2026-08-15T14:02:11Z")
      expect(recorded["streaming"]).to eq("claimed" => true, "result" => "pass", "checked_at" => "2026-08-15T14:02:11Z")
      expect(recorded["native_tool_use"]).to eq("claimed" => true, "result" => "pass", "checked_at" => now.iso8601)
    end

    it "sets last_full_run_at only when ran_full_unskipped is true" do
      entry = entry_for(:anthropic_old_model)
      now = Time.utc(2026, 8, 19, 12, 0, 0)

      described_class.record!(entry, { "completion" => capability_result(:pass) }, ran_full_unskipped: false, now: now)
      node = raw_yaml.fetch("models").find { |m| m["key"] == "anthropic_old_model" }
      expect(node["verification"]).not_to have_key("last_full_run_at")

      described_class.record!(entry_for(:anthropic_old_model), { "completion" => capability_result(:pass) }, ran_full_unskipped: true, now: now)
      node = raw_yaml.fetch("models").find { |m| m["key"] == "anthropic_old_model" }
      expect(node["verification"]["last_full_run_at"]).to eq(now.iso8601)
    end

    it "overwrites an existing last_full_run_at when ran_full_unskipped is true" do
      entry = entry_for(:anthropic_test_model)
      now = Time.utc(2026, 8, 19, 12, 0, 0)

      described_class.record!(entry, { "completion" => capability_result(:pass) }, ran_full_unskipped: true, now: now)

      node = raw_yaml.fetch("models").find { |m| m["key"] == "anthropic_test_model" }
      expect(node["verification"]["last_full_run_at"]).to eq(now.iso8601)
    end

    it "records against the correct open_ai endpoint node and leaves the sibling endpoint untouched" do
      entry = open_ai_entry_for("gpt_test", "completions")
      now = Time.utc(2026, 8, 19, 12, 0, 0)

      described_class.record!(entry, { "completion" => capability_result(:pass) }, ran_full_unskipped: false, now: now)

      model = raw_open_ai_yaml.fetch("models").find { |m| m["key_base"] == "gpt_test" }
      expect(model["endpoints"]["completions"]["verification"]["results"]["completion"]).to eq(
        "claimed" => true,
        "result" => "pass",
        "checked_at" => now.iso8601
      )
      expect(model["endpoints"]["responses"]["verification"]).to be_nil
    end

    it "does not disturb an unrelated model in the same provider file" do
      entry = entry_for(:anthropic_old_model)

      described_class.record!(entry, { "completion" => capability_result(:pass) }, ran_full_unskipped: false)

      untouched = raw_yaml.fetch("models").find { |m| m["key"] == "anthropic_test_model" }
      expect(untouched["verification"]["results"].keys).to contain_exactly("completion", "streaming")
    end

    it "preserves Date objects for untouched lifecycle fields on write" do
      entry = entry_for(:anthropic_old_model)

      described_class.record!(entry, { "completion" => capability_result(:pass) }, ran_full_unskipped: false)

      node = raw_yaml.fetch("models").find { |m| m["key"] == "anthropic_old_model" }
      expect(node["lifecycle"]["added_on"]).to eq(Date.new(2024, 1, 1))
      expect(node["lifecycle"]["added_on"]).to be_a(Date)
    end

    it "round-trips through a reload: checked_at is readable, claimed matches, capability drops out of unverified_capabilities" do
      entry = entry_for(:anthropic_old_model)
      before_unverified = entry.unverified_capabilities

      now = Time.utc(2026, 8, 19, 12, 0, 0)
      described_class.record!(entry, { "completion" => capability_result(:pass) }, ran_full_unskipped: false, now: now)

      reloaded_entry = entry_for(:anthropic_old_model)
      record = reloaded_entry.verification["results"]["completion"]

      expect(Time.parse(record["checked_at"])).to eq(now)
      expect(record["claimed"]).to eq(reloaded_entry.claimed_value("completion"))

      expect(reloaded_entry.unverified_capabilities).not_to include("completion")
      expect(reloaded_entry.unverified_capabilities.size).to eq(before_unverified.size - 1)
    end

    it "keeps the written file valid: verification results keys stay within smokable_capabilities and each record has claimed/result/checked_at" do
      entry = entry_for(:anthropic_old_model)
      open_ai_entry = open_ai_entry_for("gpt_test", "completions")

      described_class.record!(
        entry,
        { "completion" => capability_result(:pass), "native_tool_use" => capability_result(:fail) },
        ran_full_unskipped: true
      )
      described_class.record!(open_ai_entry, { "completion" => capability_result(:pass) }, ran_full_unskipped: false)

      manifest.llm_entries.each do |reloaded_entry|
        results = reloaded_entry.verification&.dig("results") || {}
        expect(results.keys - reloaded_entry.smokable_capabilities).to be_empty

        results.each_value do |record|
          expect(record).to include("claimed", "result", "checked_at")
        end
      end
    end
  end
end
