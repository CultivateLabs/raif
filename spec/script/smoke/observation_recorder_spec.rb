# frozen_string_literal: true

require "rails_helper"
require "raif/model_manifest"
require Raif::Engine.root.join("script/smoke/observation_recorder")
require "tmpdir"
require "json"

RSpec.describe Smoke::ObservationRecorder do
  let(:manifest_fixture_dir) { Raif::Engine.root.join("spec/fixtures/model_manifest").to_s }
  let(:manifest) { Raif::ModelManifest.load(dir: manifest_fixture_dir) }
  let(:anthropic_test_model) { manifest.llm_entries.find { |e| e.key == :anthropic_test_model } }
  let(:anthropic_old_model) { manifest.llm_entries.find { |e| e.key == :anthropic_old_model } }
  let(:open_ai_completions_entry) { manifest.llm_entries.find { |e| e.key == :open_ai_gpt_test } }
  let(:embedding_entry) { manifest.embedding_entries.find { |e| e.key == :open_ai_test_embedding } }

  let(:entries_by_key) do
    (manifest.llm_entries + manifest.embedding_entries).index_by { |entry| entry.key.to_s }
  end

  let(:fixed_now) { Time.utc(2026, 8, 24, 12, 0, 0) }

  around do |example|
    Dir.mktmpdir("raif-observation-recorder-spec") do |dir|
      @tmp_dir = dir
      example.run
    end
  end

  def capability_result(status, detail: "detail", recordable: nil)
    result = { status: status, detail: detail }
    result[:recordable] = recordable unless recordable.nil?
    result
  end

  def model_result(key, capabilities)
    { key: key.to_s, explicit: false, capabilities: capabilities }
  end

  def read_json(filename)
    JSON.parse(File.read(File.join(@tmp_dir, filename)))
  end

  def write_json(filename, payload)
    File.write(File.join(@tmp_dir, filename), JSON.pretty_generate(payload) + "\n")
  end

  describe ".record_all!" do
    it "writes one provider-named JSON file for a provider with at least one recordable pass" do
      model_results = [model_result(anthropic_test_model.key, { "native_tool_use" => capability_result(:pass) })]

      described_class.record_all!(model_results, entries_by_key: entries_by_key, dir: @tmp_dir, now: fixed_now)

      expect(File.exist?(File.join(@tmp_dir, "anthropic.json"))).to be(true)
    end

    it "merges untouched prior observations: an existing pass for capability X survives a run recording capability Y" do
      write_json("anthropic.json", {
        "schema_version" => 1,
        "models" => {
          "anthropic_test_model" => {
            "completion" => { "claimed" => true, "result" => "pass", "checked_at" => "2026-08-01T00:00:00Z" }
          }
        }
      })

      model_results = [model_result(anthropic_test_model.key, { "streaming" => capability_result(:pass) })]
      described_class.record_all!(model_results, entries_by_key: entries_by_key, dir: @tmp_dir, now: fixed_now)

      recorded = read_json("anthropic.json").dig("models", "anthropic_test_model")
      expect(recorded["completion"]).to eq("claimed" => true, "result" => "pass", "checked_at" => "2026-08-01T00:00:00Z")
      expect(recorded["streaming"]).to eq("claimed" => true, "result" => "pass", "checked_at" => fixed_now.iso8601)
    end

    it "keeps a prior recorded pass when a later run fails that same capability" do
      write_json("anthropic.json", {
        "schema_version" => 1,
        "models" => {
          "anthropic_test_model" => {
            "streaming" => { "claimed" => true, "result" => "pass", "checked_at" => "2026-08-01T00:00:00Z" }
          }
        }
      })

      model_results = [model_result(anthropic_test_model.key, { "streaming" => capability_result(:fail) })]
      described_class.record_all!(model_results, entries_by_key: entries_by_key, dir: @tmp_dir, now: fixed_now)

      recorded = read_json("anthropic.json").dig("models", "anthropic_test_model")
      expect(recorded["streaming"]).to eq("claimed" => true, "result" => "pass", "checked_at" => "2026-08-01T00:00:00Z")
    end

    it "updates claimed, result, and checked_at for a newly observed pass" do
      write_json("anthropic.json", {
        "schema_version" => 1,
        "models" => {
          "anthropic_old_model" => {
            "native_tool_use" => { "claimed" => false, "result" => "pass", "checked_at" => "2026-08-01T00:00:00Z" }
          }
        }
      })

      model_results = [model_result(anthropic_old_model.key, { "native_tool_use" => capability_result(:pass) })]
      described_class.record_all!(model_results, entries_by_key: entries_by_key, dir: @tmp_dir, now: fixed_now)

      recorded = read_json("anthropic.json").dig("models", "anthropic_old_model", "native_tool_use")
      expect(recorded).to eq(
        "claimed" => anthropic_old_model.claimed_value("native_tool_use"),
        "result" => "pass",
        "checked_at" => fixed_now.iso8601
      )
    end

    it "ignores fail, note, skip, timeout, and recordable: false outcomes" do
      model_results = [model_result(anthropic_test_model.key, {
        "native_tool_use" => capability_result(:fail),
        "temperature" => capability_result(:note),
        "streaming" => capability_result(:skip),
        "batch_inference" => capability_result(:timeout),
        "structured_outputs" => capability_result(:pass, detail: "json_response_tool", recordable: false)
      })]

      described_class.record_all!(model_results, entries_by_key: entries_by_key, dir: @tmp_dir, now: fixed_now)

      expect(File.exist?(File.join(@tmp_dir, "anthropic.json"))).to be(false)
    end

    it "never opens or writes any file under model_manifest/ (the manifest fixtures stay byte-identical)" do
      manifest_path = File.join(manifest_fixture_dir, "anthropic.rb")
      before_contents = File.read(manifest_path)

      model_results = [model_result(anthropic_test_model.key, { "completion" => capability_result(:pass) })]
      described_class.record_all!(model_results, entries_by_key: entries_by_key, dir: @tmp_dir, now: fixed_now)

      expect(File.read(manifest_path)).to eq(before_contents)
    end

    it "writes nothing at all when the run contains no recordable results" do
      model_results = [model_result(anthropic_test_model.key, { "temperature" => capability_result(:note) })]

      described_class.record_all!(model_results, entries_by_key: entries_by_key, dir: @tmp_dir, now: fixed_now)

      expect(Dir.children(@tmp_dir)).to be_empty
    end

    it "raises a contextual error naming the file instead of merging and downgrading a future schema_version" do
      write_json("anthropic.json", {
        "schema_version" => 2,
        "models" => {
          "anthropic_test_model" => {
            "completion" => { "claimed" => true, "result" => "pass", "checked_at" => "2026-08-01T00:00:00Z" }
          }
        }
      })

      model_results = [model_result(anthropic_test_model.key, { "streaming" => capability_result(:pass) })]

      expect {
        described_class.record_all!(model_results, entries_by_key: entries_by_key, dir: @tmp_dir, now: fixed_now)
      }.to raise_error(/anthropic\.json/)
    end

    it "records LLM and embedding results for the same provider in one write" do
      model_results = [
        model_result(open_ai_completions_entry.key, { "completion" => capability_result(:pass) }),
        model_result(embedding_entry.key, { "embedding" => capability_result(:pass) })
      ]

      described_class.record_all!(model_results, entries_by_key: entries_by_key, dir: @tmp_dir, now: fixed_now)

      models = read_json("open_ai.json").fetch("models")
      expect(models.keys).to contain_exactly(open_ai_completions_entry.key.to_s, embedding_entry.key.to_s)
      expect(models[embedding_entry.key.to_s]["embedding"]).to eq(
        "claimed" => true, "result" => "pass", "checked_at" => fixed_now.iso8601
      )
    end

    it "emits sorted model and capability keys, pretty JSON, and is byte-for-byte idempotent on a repeated run" do
      model_results = [
        model_result(anthropic_old_model.key, { "streaming" => capability_result(:pass), "completion" => capability_result(:pass) }),
        model_result(anthropic_test_model.key, { "native_tool_use" => capability_result(:pass) })
      ]

      described_class.record_all!(model_results, entries_by_key: entries_by_key, dir: @tmp_dir, now: fixed_now)
      first_contents = File.read(File.join(@tmp_dir, "anthropic.json"))
      parsed = JSON.parse(first_contents)

      expect(parsed["models"].keys).to eq(%w[anthropic_old_model anthropic_test_model])
      expect(parsed.dig("models", "anthropic_old_model").keys).to eq(%w[completion streaming])
      expect(first_contents).to eq(JSON.pretty_generate(parsed) + "\n")

      described_class.record_all!(model_results, entries_by_key: entries_by_key, dir: @tmp_dir, now: fixed_now)
      second_contents = File.read(File.join(@tmp_dir, "anthropic.json"))

      expect(second_contents).to eq(first_contents)
    end
  end
end
