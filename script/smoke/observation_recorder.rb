# frozen_string_literal: true

require "json"
require "fileutils"
require "raif/model_manifest/smoke_observations"
require_relative "policy"

# Writes durable smoke-test evidence to model_smoke_results/*.json once a full bin/smoke run
# completes. Turns a run_all-shaped model_results array into the per-provider JSON files that
# Raif::ModelManifest::SmokeObservations reads back.
#
# Only touches model_smoke_results/*.json; never opens or writes lib/raif/model_manifest/definitions/*.rb. A
# provider's existing file is merged, never replaced: a capability this run did not positively
# re-observe keeps whatever was already on file, so a later run's failure never withdraws a
# previously recorded pass. Withdrawing durable evidence is a human decision, not something an
# automated run makes for itself.
#
# Only references entries_by_key values (Raif::ModelManifest::Entry / EmbeddingEntry) and plain
# hashes, so this loads standalone and can be unit-tested without Raif or a live API booted.
module Smoke
  module ObservationRecorder
    # model_results - the array run_all returns: [{ key:, explicit:, capabilities: { name => { status:, detail:, recordable: (optional) } } }].
    # entries_by_key - String model key => Raif::ModelManifest::Entry/EmbeddingEntry, used to resolve
    #   each entry's provider_name (the destination file) and claimed_value (the recorded claim).
    # dir - the model_smoke_results directory to read existing observations from and write into.
    # now - injected for deterministic specs; defaults to the real current time.
    def self.record_all!(model_results, entries_by_key:, dir:, now: Time.now.utc)
      new_observations_by_provider(model_results, entries_by_key, now).each do |provider_name, observations|
        write_provider_file(provider_name, observations, dir)
      end
    end

    # provider_name => { model_key => { capability => { "claimed" =>, "result" => "pass", "checked_at" => } } },
    # containing only the capabilities this run positively observed as a recordable pass. A
    # provider with nothing recordable this run never appears, so record_all! never opens or
    # writes its file.
    def self.new_observations_by_provider(model_results, entries_by_key, now)
      grouped = {}

      model_results.each do |model_result|
        entry = entries_by_key.fetch(model_result[:key])

        model_result[:capabilities].each do |capability, result|
          next unless Policy.recordable?(capability, result)

          provider_models = (grouped[entry.provider_name] ||= {})
          (provider_models[model_result[:key]] ||= {})[capability.to_s] = {
            "claimed" => claimed_value_for(entry, capability),
            "result" => "pass",
            "checked_at" => now.iso8601
          }
        end
      end

      grouped
    end
    private_class_method :new_observations_by_provider

    # Derived candidates are true by construction (see SmokeObservations::DERIVED_CAPABILITIES).
    # Every other capability's claim comes straight from the manifest entry, run through the same
    # normalization #fresh? applies when reading a claim back, so an array claim (e.g.
    # provider_managed_tools) round trips through JSON as the same value #fresh? will compare against.
    def self.claimed_value_for(entry, capability)
      return true if Raif::ModelManifest::SmokeObservations::DERIVED_CAPABILITIES.include?(capability.to_sym)

      Raif::ModelManifest::SmokeObservations.normalize_claim(entry.claimed_value(capability.to_s))
    end
    private_class_method :claimed_value_for

    def self.write_provider_file(provider_name, observations, dir)
      path = File.join(dir, "#{provider_name}.json")
      payload = { "schema_version" => Raif::ModelManifest::SmokeObservations::SCHEMA_VERSION, "models" => merged_models(path, observations) }

      write_atomically(path, JSON.pretty_generate(payload) + "\n")
    end
    private_class_method :write_provider_file

    # Merges this run's newly observed capabilities over whatever the provider's file already
    # holds, capability by capability, so an untouched capability on an untouched model survives
    # unchanged and a model this run never selected survives entirely untouched. Sorts both model
    # keys and, within each model, capability keys, so the written file is deterministic.
    def self.merged_models(path, observations)
      existing = existing_models(path)
      merged = existing.merge(observations) { |_key, old_capabilities, new_capabilities| old_capabilities.merge(new_capabilities) }

      merged.keys.sort.to_h { |key| [key, merged[key].sort.to_h] }
    end
    private_class_method :merged_models

    def self.existing_models(path)
      return {} unless File.exist?(path)

      data = JSON.parse(File.read(path))
      validate_schema_version!(data, path)
      data.fetch("models", {})
    end
    private_class_method :existing_models

    # Symmetric with SmokeObservations.load's own rejection: a provider file written by some
    # future schema version must never be silently merged and restamped back down to
    # SCHEMA_VERSION, which would downgrade it and quietly discard whatever the newer schema added.
    def self.validate_schema_version!(data, path)
      version = data["schema_version"]
      return if version == Raif::ModelManifest::SmokeObservations::SCHEMA_VERSION

      raise ArgumentError,
        "ObservationRecorder: unknown schema_version #{version.inspect} in #{path} " \
        "(expected #{Raif::ModelManifest::SmokeObservations::SCHEMA_VERSION})"
    end
    private_class_method :validate_schema_version!

    # Writes through a temp file in the same directory, then File.rename, so an interrupted
    # process cannot leave a truncated or partially-written JSON file on disk.
    def self.write_atomically(path, contents)
      FileUtils.mkdir_p(File.dirname(path))
      tmp_path = "#{path}.tmp#{Process.pid}"
      File.write(tmp_path, contents)
      File.rename(tmp_path, path)
    end
    private_class_method :write_atomically
  end
end
