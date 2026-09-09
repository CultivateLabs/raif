#!/usr/bin/env ruby
# frozen_string_literal: true

# Reports which claimed, recordable model capabilities have a usable smoke
# observation, grouped by provider. Read-only: it never writes a file, never
# hits a provider API, and never runs bin/smoke.
#
# This exists for the scheduled drift check
# (.github/workflows/model-manifest-check.yml), which has a narrow tool
# allowlist. Reconciling model_smoke_results/*.json against the manifest needs
# shell pipelines (jq into sort into comm), and prefix-based permission rules do
# not match a piped command, so the check could not do it. One allowlisted
# command replaces that, and keeps the arithmetic somewhere testable.
#
# Unlike bin/smoke this runs as plain Ruby with no Rails: lib/raif/model_manifest
# resolves its definitions relative to __dir__, and SmokeObservations.load only
# needs Rails for the default value of dir:, which is passed explicitly here.
#
# Usage:
#   script/drift/manifest_coverage.rb          # human-readable summary
#   script/drift/manifest_coverage.rb --json   # machine-readable, for the check
#   script/drift/manifest_coverage.rb --stale-days 30

require "json"
require "optparse"
require "time"

$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require "raif/model_manifest"
require "raif/model_manifest/smoke_observations"

REPO_ROOT = File.expand_path("../..", __dir__)
RESULTS_DIR = File.join(REPO_ROOT, "model_smoke_results")

# Large enough that fresh? disregards age, which separates "is there a passing
# observation whose recorded claim still matches the manifest" from "is it old".
ANY_AGE_DAYS = 100_000

options = { json: false, stale_days: 90 }
OptionParser.new do |parser|
  parser.banner = "Usage: script/drift/manifest_coverage.rb [--json] [--stale-days N]"
  parser.on("--json", "Emit JSON instead of a human-readable summary") { options[:json] = true }
  parser.on("--stale-days N", Integer, "Age at which an observation counts as stale (default 90)") do |n|
    options[:stale_days] = n
  end
end.parse!

manifest = Raif::ModelManifest.load
observations = Raif::ModelManifest::SmokeObservations.load(dir: RESULTS_DIR)
now = Time.now.utc

# Re-read for timestamps, and to tell "no results file yet" apart from "file
# exists, these capabilities missing from it": the store merges every file into
# one keyspace and exposes no per-file view.
raw_timestamps = {}
Dir[File.join(RESULTS_DIR, "*.json")].sort.each do |path|
  provider = File.basename(path, ".json").to_sym
  stamps = []
  JSON.parse(File.read(path)).fetch("models", {}).each_value do |capabilities|
    capabilities.each_value do |record|
      stamps << Time.parse(record["checked_at"]) if record["checked_at"]
    end
  end
  raw_timestamps[provider] = stamps
end

# Retired entries are excluded to match script/smoke/selection.rb, which never
# selects them, so the check does not report coverage gaps for models the smoke
# runner would refuse to test.
entries = (manifest.llm_entries + manifest.embedding_entries).reject(&:retired?)

providers = {}

entries.group_by(&:provider_name).sort.each do |provider_name, provider_entries|
  models = {}
  never_observed_counts = Hash.new(0)
  candidate_counts = Hash.new(0)

  provider_entries.sort_by { |entry| entry.key.to_s }.each do |entry|
    candidates = Raif::ModelManifest::SmokeObservations.recordable_candidates(entry)

    unobserved = []
    stale = []
    candidates.each do |capability|
      candidate_counts[capability] += 1
      if observations.fresh?(entry, capability, stale_after_days: ANY_AGE_DAYS, now: now)
        unless observations.fresh?(entry, capability, stale_after_days: options[:stale_days], now: now)
          stale << capability
        end
      else
        unobserved << capability
        never_observed_counts[capability] += 1
      end
    end

    next if unobserved.empty? && stale.empty?

    models[entry.key] = {
      status: entry.status,
      candidate_count: candidates.length,
      unobserved: unobserved.sort,
      stale: stale.sort,
      wholly_unobserved: unobserved.length == candidates.length
    }
  end

  stamps = raw_timestamps[provider_name] || []
  total_candidates = candidate_counts.values.sum
  total_unobserved = never_observed_counts.values.sum

  # A capability every entry claims and none has an observation for is a
  # systemic gap, not a per-model one, and is worth stating once.
  systemic = candidate_counts.select { |cap, n| never_observed_counts[cap] == n }.keys.sort

  providers[provider_name] = {
    results_file: "model_smoke_results/#{provider_name}.json",
    results_file_present: File.exist?(File.join(RESULTS_DIR, "#{provider_name}.json")),
    observation_count: stamps.length,
    oldest_checked_at: stamps.min&.iso8601,
    newest_checked_at: stamps.max&.iso8601,
    entry_count: provider_entries.length,
    candidate_count: total_candidates,
    unobserved_count: total_unobserved,
    stale_count: models.values.sum { |m| m[:stale].length },
    capabilities_never_observed: systemic,
    models_with_no_observations: models.select { |_k, m| m[:wholly_unobserved] }.keys.sort,
    models: models
  }
end

report = {
  generated_at: now.iso8601,
  stale_after_days: options[:stale_days],
  note: "Counts cover claimed, recordable capabilities on non-retired entries. " \
        "A capability is unobserved when there is no passing observation whose recorded claim still matches the manifest.",
  providers: providers
}

if options[:json]
  puts JSON.pretty_generate(report)
else
  puts "Manifest smoke coverage as of #{report[:generated_at]} (stale after #{options[:stale_days]} days)"
  puts
  providers.each do |provider_name, data|
    puts "#{provider_name}: #{data[:unobserved_count]} of #{data[:candidate_count]} candidates unobserved, " \
         "#{data[:stale_count]} stale"
    puts "  results file: #{data[:results_file_present] ? data[:results_file] : "MISSING (#{data[:results_file]})"}"
    puts "  oldest observation: #{data[:oldest_checked_at] || "none"}"
    unless data[:capabilities_never_observed].empty?
      puts "  never observed for any entry: #{data[:capabilities_never_observed].join(", ")}"
    end
    unless data[:models_with_no_observations].empty?
      puts "  no observation at all: #{data[:models_with_no_observations].join(", ")}"
    end
    puts
  end
end
