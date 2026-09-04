# frozen_string_literal: true

# Read-only store for smoke-test evidence recorded under model_smoke_results/*.json.
# This class never writes; Smoke::ObservationRecorder owns writing. Loading here
# never mutates the manifest entries it is asked about, and the loaded data is
# deeply frozen so a caller cannot accidentally corrupt cached observations mid-run.
require "raif/model_manifest"
require "json"
require "time"

module Raif
  module ModelManifest
    class SmokeObservations
      SCHEMA_VERSION = 1

      # The complete set of capabilities `bin/smoke --record` may write as a durable
      # pass; the single source of truth referenced by Smoke::Policy and
      # Smoke::ObservationRecorder. temperature is intentionally absent: an accepted
      # request does not prove the model honored the parameter.
      RECORDABLE_POSITIVE_CAPABILITIES = %i[
        completion structured_outputs native_tool_use streaming
        streaming_tool_calls batch_inference images pdfs
        provider_managed_tools embedding
      ].freeze

      # Capabilities that are not literal manifest capability keys: their "claimed"
      # state is derived from other capabilities. They are only ever offered as
      # candidates when their preconditions are claimed, so their current claim is
      # true by construction (for :embedding this is also the only option:
      # EmbeddingEntry has no claimed_value method to call).
      DERIVED_CAPABILITIES = %i[completion streaming_tool_calls embedding].freeze

      def self.load(dir: Raif::Engine.root.join("model_smoke_results"))
        models = {}

        Dir[File.join(dir, "*.json")].sort.each do |path|
          data = parse_json(path)
          validate_schema_version!(data, path)

          data.fetch("models", {}).each do |model_key, capabilities|
            capabilities.each do |capability_name, record|
              checked_at = parse_checked_at(record["checked_at"], path: path, model_key: model_key, capability: capability_name)

              (models[model_key.to_sym] ||= {})[capability_name.to_sym] = {
                claimed: record.fetch("claimed"),
                result: record.fetch("result"),
                checked_at: checked_at
              }
            end
          end
        end

        new(models)
      end

      # EmbeddingEntry -> [:embedding]; an LLM entry -> :completion plus every
      # positively claimed recordable capability, plus :streaming_tool_calls only
      # when streaming AND native_tool_use are both claimed, plus
      # :provider_managed_tools only when the declared tool list is non-empty.
      def self.recordable_candidates(entry)
        return [:embedding] if entry.is_a?(EmbeddingEntry)

        candidates = [:completion]
        candidates << :structured_outputs if entry.claimed_value("structured_outputs")
        candidates << :native_tool_use if entry.claimed_value("native_tool_use")
        candidates << :streaming if entry.claimed_value("streaming")
        candidates << :streaming_tool_calls if entry.claimed_value("streaming") && entry.claimed_value("native_tool_use")
        candidates << :batch_inference if entry.claimed_value("batch_inference")
        candidates << :images if entry.claimed_value("images")
        candidates << :pdfs if entry.claimed_value("pdfs")
        candidates << :provider_managed_tools if entry.claimed_value("provider_managed_tools")&.any?
        candidates
      end

      def self.parse_json(path)
        JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        raise ArgumentError, "SmokeObservations: malformed JSON in #{path}: #{e.message}"
      end
      private_class_method :parse_json

      def self.validate_schema_version!(data, path)
        version = data["schema_version"]
        return if version == SCHEMA_VERSION

        raise ArgumentError, "SmokeObservations: unknown schema_version #{version.inspect} in #{path} (expected #{SCHEMA_VERSION})"
      end
      private_class_method :validate_schema_version!

      def self.parse_checked_at(value, path:, model_key:, capability:)
        Time.iso8601(value.to_s)
      rescue ArgumentError
        raise ArgumentError, "SmokeObservations: malformed checked_at #{value.inspect} for #{model_key}/#{capability} in #{path}"
      end
      private_class_method :parse_checked_at

      # The single normalization both Smoke::ObservationRecorder (writing) and #fresh? (reading
      # back, on both the stored and the live side) run a claim through, so a claim's shape never
      # depends on which side of a JSON round trip it is on. A boolean claim passes through
      # unchanged. An array claim (only provider_managed_tools today) is a symbol array on a live
      # manifest entry but a string array once it has been through JSON, so both sides are
      # stringified and sorted before comparison.
      def self.normalize_claim(value)
        return value.map(&:to_s).sort if value.is_a?(Array)

        value
      end

      def initialize(models)
        @models = deep_freeze(models)
        freeze
      end

      def fresh?(entry, capability, stale_after_days: 30, now: Time.now.utc)
        capability = capability.to_sym
        record = @models.dig(entry.key, capability)
        return false unless record
        return false if record[:result] != "pass"
        return false if self.class.normalize_claim(record[:claimed]) != self.class.normalize_claim(current_claim(entry, capability))

        !stale_by_age?(record[:checked_at], stale_after_days: stale_after_days, now: now)
      end

      def stale_capabilities(entry, stale_after_days: 30, now: Time.now.utc)
        self.class.recordable_candidates(entry).reject { |cap| fresh?(entry, cap, stale_after_days:, now:) }
      end

    private

      # Derived candidates are true by construction (see DERIVED_CAPABILITIES); for
      # everything else the entry's manifest claim is authoritative, read via
      # claimed_value's string-keyed API.
      def current_claim(entry, capability)
        return true if DERIVED_CAPABILITIES.include?(capability)

        entry.claimed_value(capability.to_s)
      end

      def stale_by_age?(checked_at, stale_after_days:, now:)
        checked_at < (now - (stale_after_days * 86_400))
      end

      def deep_freeze(obj)
        case obj
        when Hash
          obj.each do |k, v|
            deep_freeze(k)
            deep_freeze(v)
          end
        when Array
          obj.each { |v| deep_freeze(v) }
        end
        obj.freeze
      end
    end
  end
end
