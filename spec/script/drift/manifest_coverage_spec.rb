# frozen_string_literal: true

require "rails_helper"
require "json"
require "open3"
require "raif/model_manifest"

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
end
