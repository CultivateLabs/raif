# frozen_string_literal: true

require "rails_helper"
require "json"
require "open3"
require "fileutils"
require "tmpdir"
require "raif/model_manifest"
require "raif/model_manifest/smoke_observations"

# Invariants rather than counts: the numbers move whenever a model is added or
# smoked. What matters is that the scheduled drift check can run this and trust
# the arithmetic, so these cover the properties it depends on.
RSpec.describe "script/drift/manifest_coverage.rb" do
  script = Raif::Engine.root.join("script/drift/manifest_coverage.rb").to_s

  # Invoked through a bare ruby, not rails runner, because the workflow that
  # depends on this has no Ruby or Bundler setup and relies on the script
  # loading the manifest without Rails.
  stdout, stderr, status = Open3.capture3(RbConfig.ruby, script, "--json")

  it "exits successfully" do
    expect(status).to be_success, "stderr: #{stderr}"
  end

  it "emits parseable JSON with the keys the check reads" do
    report = JSON.parse(stdout)
    expect(report.keys).to include("generated_at", "stale_after_days", "providers")
  end

  it "covers every provider the manifest declares" do
    report = JSON.parse(stdout)
    declared = Raif::ModelManifest.load.llm_entries.map { |entry| entry.provider_name.to_s }.uniq
    expect(report["providers"].keys).to include(*declared)
  end

  it "reports an unobserved count matching the per-model detail" do
    report = JSON.parse(stdout)

    report["providers"].each do |provider, data|
      from_models = data["models"].values.sum { |model| model["unobserved"].length }
      expect(data["unobserved_count"]).to eq(from_models),
        "#{provider}: unobserved_count #{data["unobserved_count"]} but per-model detail sums to #{from_models}"
    end
  end

  it "never counts more candidates as unobserved than exist" do
    report = JSON.parse(stdout)

    report["providers"].each_value do |data|
      expect(data["unobserved_count"]).to be <= data["candidate_count"]
    end
  end

  # Vacuous while nothing in the manifest is retired, which is the case today.
  # It is here to fail the moment an entry is retired and the script stops
  # filtering, not as evidence that the filtering works now.
  it "excludes retired entries, which the smoke runner never selects" do
    report = JSON.parse(stdout)
    manifest = Raif::ModelManifest.load
    retired = (manifest.llm_entries + manifest.embedding_entries).select(&:retired?).map { |entry| entry.key.to_s }

    reported = report["providers"].values.flat_map { |data| data["models"].keys }
    expect(reported & retired).to be_empty
  end

  it "writes nothing" do
    expect { Open3.capture3(RbConfig.ruby, script, "--json") }
      .not_to(change { Dir[Raif::Engine.root.join("model_smoke_results/*.json")].map { |f| File.mtime(f) } })
  end

  describe "the compact report" do
    around do |example|
      Dir.mktmpdir("raif-coverage-spec") do |dir|
        @root = Pathname.new(dir)
        FileUtils.mkdir_p(@root.join("script/drift"))
        FileUtils.mkdir_p(@root.join("lib/raif/model_manifest/definitions"))
        FileUtils.mkdir_p(@root.join("model_smoke_results"))
        FileUtils.cp(script, @root.join("script/drift/manifest_coverage.rb"))
        %w[model_manifest.rb model_manifest/dsl.rb model_manifest/smoke_observations.rb].each do |path|
          FileUtils.cp(Raif::Engine.root.join("lib/raif", path), @root.join("lib/raif", path))
        end
        FileUtils.cp(
          Raif::Engine.root.join("spec/fixtures/model_manifest/anthropic.rb"),
          @root.join("lib/raif/model_manifest/definitions/anthropic.rb")
        )
        example.run
      end
    end

    let(:records) do
      manifest = Raif::ModelManifest.load(dir: @root.join("lib/raif/model_manifest/definitions"))
      manifest.llm_entries.to_h do |entry|
        capabilities = Raif::ModelManifest::SmokeObservations.recordable_candidates(entry).to_h do |capability|
          [capability, { claimed: entry.claimed_value(capability), result: "pass", checked_at: Time.now.utc.iso8601 }]
        end
        [entry.key, capabilities]
      end
    end

    def compact_report
      File.write(@root.join("model_smoke_results/anthropic.json"), JSON.generate(schema_version: 1, models: records))
      output, errors, result = Open3.capture3(RbConfig.ruby, @root.join("script/drift/manifest_coverage.rb").to_s)
      expect(result).to be_success, "stderr: #{errors}"
      output
    end

    it "identifies a changed affected set even when the missing capability count stays the same" do
      observation = records[:anthropic_test_model].delete(:images)
      before = compact_report
      expect(before).to include("anthropic_test_model: unobserved: images")
      expect(before).not_to include("anthropic_old_model:")

      records[:anthropic_test_model][:images] = observation
      records[:anthropic_old_model].delete(:images)
      after = compact_report
      expect(after).to include("anthropic_old_model: unobserved: images")
      expect(after).not_to include("anthropic_test_model:")
      expect(after.lines.grep(/^anthropic:/)).to eq(before.lines.grep(/^anthropic:/))
    end

    it "identifies stale-only models and their stale capabilities" do
      records[:anthropic_test_model][:images][:checked_at] = (Time.now.utc - (91 * 86_400)).iso8601

      expect(compact_report).to include("anthropic_test_model: stale: images")
    end
  end
end
