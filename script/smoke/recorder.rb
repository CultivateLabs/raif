# frozen_string_literal: true

require "yaml"
require "date"
require "time"
require_relative "policy"

# Writes smoke check results back into a provider's model_manifest/*.yml file. Turns a
# Smoke::Checks.run_for-shaped result hash into the verification.results block that
# Raif::ModelManifest::Entry#unverified_capabilities reads back.
#
# Only references entry (a Raif::ModelManifest::Entry) and plain hashes, so this loads standalone
# and can be unit-tested without Raif or a live API booted.
module Smoke
  module Recorder
    RESULT_STRINGS = {
      fail: "fail",
      note: "note_works_despite_claim"
    }.freeze

    # entry - a Raif::ModelManifest::Entry; entry.source_path is the provider YAML file to update.
    # capability_results - a Smoke::Checks.run_for-shaped hash: { "capability" => { status:, detail: } }.
    # ran_full_unskipped - true only when every smokable capability for entry was attempted, with
    #   nothing filtered out by --only/--skip; gates last_full_run_at so a partial run never claims a
    #   fresher full verification than it actually performed.
    # now - injected for deterministic specs; defaults to the real current time.
    def self.record!(entry, capability_results, ran_full_unskipped:, now: Time.now.utc)
      data = YAML.safe_load_file(entry.source_path, permitted_classes: [Date], aliases: true)
      node = locate_node(data, entry)

      verification = (node["verification"] ||= {})
      results = (verification["results"] ||= {})

      capability_results.each do |capability, result|
        next unless Policy.recordable?(result)

        result_string = result_string_for(capability, result)
        next if result_string.nil? # defensive: Policy.recordable? already excludes :skip/:timeout

        results[capability.to_s] = {
          "claimed" => entry.claimed_value(capability),
          "result" => result_string,
          "checked_at" => now.iso8601
        }
      end

      verification["last_full_run_at"] = now.iso8601 if ran_full_unskipped

      File.write(entry.source_path, data.to_yaml)
    end

    # Non-open_ai providers key their model node by "key"; open_ai keys the model by "key_base" and
    # nests each capability matrix under endpoints[entry.endpoint], since a single open_ai model_base
    # can have both a completions and a responses endpoint with independently-verified capabilities.
    def self.locate_node(data, entry)
      models = data.fetch("models")

      if entry.endpoint
        model = models.find { |m| m["key_base"].to_s == entry.key_base.to_s }
        raise "Smoke::Recorder: no model with key_base #{entry.key_base} in #{entry.source_path}" unless model

        model.fetch("endpoints").fetch(entry.endpoint) do
          raise "Smoke::Recorder: no #{entry.endpoint} endpoint for #{entry.key_base} in #{entry.source_path}"
        end
      else
        model = models.find { |m| m["key"].to_s == entry.key.to_s }
        raise "Smoke::Recorder: no model with key #{entry.key} in #{entry.source_path}" unless model

        model
      end
    end
    private_class_method :locate_node

    def self.result_string_for(capability, result)
      case result[:status]
      when :pass then pass_result_string(capability, result[:detail])
      when :fail, :note then RESULT_STRINGS[result[:status]]
      end
    end
    private_class_method :result_string_for

    # structured_outputs is the only capability whose detail carries a verified path
    # ("native" vs. "json_response_tool"); every other capability's pass collapses to plain "pass"
    # regardless of its detail text.
    def self.pass_result_string(capability, detail)
      return "pass" unless capability.to_s == "structured_outputs"

      case detail
      when "native" then "pass_native"
      when "json_response_tool" then "pass_json_tool"
      else "pass"
      end
    end
    private_class_method :pass_result_string
  end
end
