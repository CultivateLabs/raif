# frozen_string_literal: true

require "rails_helper"
require "raif/model_manifest"
require "raif/model_manifest/smoke_observations"
require Raif::Engine.root.join("script/smoke/observation_recorder")
require "tmpdir"
require "json"

RSpec.describe Raif::ModelManifest::SmokeObservations do
  let(:manifest_fixture_dir) { Raif::Engine.root.join("spec/fixtures/model_manifest").to_s }
  let(:manifest) { Raif::ModelManifest.load(dir: manifest_fixture_dir) }
  let(:anthropic_test_model) { manifest.llm_entries.find { |e| e.key == :anthropic_test_model } }
  let(:anthropic_old_model) { manifest.llm_entries.find { |e| e.key == :anthropic_old_model } }
  let(:embedding_entry) { manifest.embedding_entries.find { |e| e.key == :open_ai_test_embedding } }

  let(:committed_fixture_dir) { Raif::Engine.root.join("spec/fixtures/model_smoke_results").to_s }

  # 5 days after the committed fixture's checked_at ("2026-08-15T14:02:11Z"), well inside a
  # 30-day staleness window.
  let(:fixed_now) { Time.iso8601("2026-08-20T00:00:00Z") }

  around do |example|
    Dir.mktmpdir("raif-smoke-observations-spec") do |dir|
      @tmp_dir = dir
      example.run
    end
  end

  def write_json(filename, payload)
    File.write(File.join(@tmp_dir, filename), JSON.pretty_generate(payload))
  end

  describe "::RECORDABLE_POSITIVE_CAPABILITIES" do
    it "is a frozen array of symbols that excludes temperature" do
      expect(described_class::RECORDABLE_POSITIVE_CAPABILITIES).to be_frozen
      expect(described_class::RECORDABLE_POSITIVE_CAPABILITIES).to all(be_a(Symbol))
      expect(described_class::RECORDABLE_POSITIVE_CAPABILITIES).not_to include(:temperature)
    end
  end

  describe ".load" do
    it "loads the committed fixture and reports its recorded pass as fresh" do
      store = described_class.load(dir: committed_fixture_dir)
      expect(store.fresh?(anthropic_test_model, :completion, stale_after_days: 30, now: fixed_now)).to be(true)
    end

    it "loads successfully from an empty directory and reports every candidate stale" do
      store = described_class.load(dir: @tmp_dir)
      candidates = described_class.recordable_candidates(anthropic_test_model)

      expect(candidates).not_to be_empty
      expect(store.stale_capabilities(anthropic_test_model, stale_after_days: 30, now: fixed_now)).to match_array(candidates)
    end

    it "raises a contextual error naming the file when checked_at cannot be parsed" do
      write_json("broken.json", {
        "schema_version" => 1,
        "models" => {
          "anthropic_test_model" => {
            "completion" => { "claimed" => true, "result" => "pass", "checked_at" => "not-a-timestamp" }
          }
        }
      })

      expect { described_class.load(dir: @tmp_dir) }.to raise_error(/broken\.json/)
    end

    it "raises a contextual error naming the file when schema_version is unknown" do
      write_json("broken.json", { "schema_version" => 2, "models" => {} })

      expect { described_class.load(dir: @tmp_dir) }.to raise_error(/broken\.json/)
    end

    it "deeply freezes the loaded data and never mutates the manifest entries it reads" do
      before_capabilities = anthropic_test_model.capabilities.dup
      store = described_class.load(dir: committed_fixture_dir)

      models = store.instance_variable_get(:@models)
      expect(models).to be_frozen
      expect(models.dig(:anthropic_test_model, :completion)).to be_frozen
      expect(models.dig(:anthropic_test_model, :completion)[:result]).to be_frozen
      expect(models.dig(:anthropic_test_model, :completion)[:checked_at]).to be_frozen

      store.stale_capabilities(anthropic_test_model, stale_after_days: 30, now: fixed_now)
      described_class.recordable_candidates(anthropic_test_model)

      expect(anthropic_test_model.capabilities).to eq(before_capabilities)
    end
  end

  describe "provider_managed_tools claim round trip through Smoke::ObservationRecorder (regression)" do
    # anthropic_test_model claims provider_managed_tools: %i[web_search code_execution], a symbol
    # array. The recorder used to write that array straight to JSON, so a load-back parsed it as
    # strings and every recorded provider_managed_tools pass compared unequal to the live symbol
    # claim forever, permanently re-selecting the model under --stale.
    def record_provider_managed_tools_pass(entry, dir)
      model_results = [{
        key: entry.key.to_s,
        explicit: false,
        capabilities: { "provider_managed_tools" => { status: :pass, detail: "web_search, code_execution" } }
      }]

      Smoke::ObservationRecorder.record_all!(
        model_results, entries_by_key: { entry.key.to_s => entry }, dir: dir, now: fixed_now
      )
    end

    it "round trips a recorded pass as fresh, and detects a real claim change as stale" do
      record_provider_managed_tools_pass(anthropic_test_model, @tmp_dir)
      store = described_class.load(dir: @tmp_dir)

      expect(store.fresh?(anthropic_test_model, :provider_managed_tools, stale_after_days: 30, now: fixed_now)).to be(true)

      # Same key, a different (narrower) declared tool list, simulating a manifest edit made after
      # the observation was recorded.
      edited_entry = anthropic_test_model.dup
      edited_entry.capabilities = anthropic_test_model.capabilities.merge(provider_managed_tools: %i[web_search])

      expect(store.fresh?(edited_entry, :provider_managed_tools, stale_after_days: 30, now: fixed_now)).to be(false)
    end
  end

  describe "#fresh?" do
    it "is stale when there is no observation on file at all" do
      store = described_class.load(dir: committed_fixture_dir)
      expect(store.fresh?(anthropic_test_model, :native_tool_use, stale_after_days: 30, now: fixed_now)).to be(false)
    end

    it "is stale when the observation is older than stale_after_days" do
      store = described_class.load(dir: committed_fixture_dir)
      far_future = Time.iso8601("2026-08-15T14:02:11Z") + (31 * 86_400)

      expect(store.fresh?(anthropic_test_model, :completion, stale_after_days: 30, now: far_future)).to be(false)
    end

    it "is stale when the stored claimed value differs from the entry's current claim" do
      write_json("anthropic.json", {
        "schema_version" => 1,
        "models" => {
          "anthropic_test_model" => {
            # the manifest fixture claims streaming: true; recording claimed: false simulates
            # a manifest edit made after the observation was recorded.
            "streaming" => { "claimed" => false, "result" => "pass", "checked_at" => fixed_now.iso8601 }
          }
        }
      })
      store = described_class.load(dir: @tmp_dir)

      expect(store.fresh?(anthropic_test_model, :streaming, stale_after_days: 30, now: fixed_now)).to be(false)
    end

    it "never treats a non-pass result as fresh, even if recently checked with a matching claim" do
      write_json("anthropic.json", {
        "schema_version" => 1,
        "models" => {
          "anthropic_test_model" => {
            "streaming" => { "claimed" => true, "result" => "fail", "checked_at" => fixed_now.iso8601 }
          }
        }
      })
      store = described_class.load(dir: @tmp_dir)

      expect(store.fresh?(anthropic_test_model, :streaming, stale_after_days: 30, now: fixed_now)).to be(false)
    end

    it "accepts the capability name as a string or a symbol" do
      store = described_class.load(dir: committed_fixture_dir)
      expect(store.fresh?(anthropic_test_model, "completion", stale_after_days: 30, now: fixed_now)).to be(true)
    end
  end

  describe ".recordable_candidates" do
    it "returns [:embedding] for an embedding entry" do
      expect(described_class.recordable_candidates(embedding_entry)).to eq([:embedding])
    end

    it "always includes :completion for an LLM entry" do
      expect(described_class.recordable_candidates(anthropic_test_model)).to include(:completion)
    end

    it "excludes a capability the manifest claims false" do
      expect(described_class.recordable_candidates(anthropic_old_model)).not_to include(:structured_outputs)
    end

    it "excludes provider_managed_tools when the declared tool list is empty" do
      expect(described_class.recordable_candidates(anthropic_old_model)).not_to include(:provider_managed_tools)
    end

    it "includes provider_managed_tools when the declared tool list is non-empty" do
      expect(described_class.recordable_candidates(anthropic_test_model)).to include(:provider_managed_tools)
    end

    it "never includes temperature, even though it is a manifest capability" do
      expect(described_class.recordable_candidates(anthropic_test_model)).not_to include(:temperature)
      expect(described_class.recordable_candidates(anthropic_old_model)).not_to include(:temperature)
    end

    it "includes streaming_tool_calls only when streaming and native_tool_use are both claimed" do
      expect(described_class.recordable_candidates(anthropic_test_model)).to include(:streaming_tool_calls)
    end
  end

  describe "#stale_capabilities" do
    it "rejects only the fresh candidates" do
      store = described_class.load(dir: committed_fixture_dir)
      stale = store.stale_capabilities(anthropic_test_model, stale_after_days: 30, now: fixed_now)

      expect(stale).not_to include(:completion) # recorded pass, unchanged claim, within window
      expect(stale).to include(:streaming) # never recorded
    end
  end
end
