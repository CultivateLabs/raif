# frozen_string_literal: true

require "raif/model_manifest/smoke_observations"

# Decides the process exit code for a bin/smoke run, and whether a single
# capability result is trustworthy enough for `--record` to write as a
# durable smoke observation.
module Smoke
  module Policy
    TOLERABLE_STATUSES = %i[skip timeout].freeze

    # results - Array of model_result hashes: { key:, explicit:, capabilities: { name => { status:, detail: } } }.
    # explicit_keys - selector strings the caller named directly (Smoke::Selection.resolve's :explicit_keys);
    #   a model_result counts as explicit when its key is in this list or its own :explicit flag is set.
    #
    # Returns 1 when any selected model has a :fail, or ran no checks at all (an empty capabilities
    # hash - an unexecuted required check); this holds regardless of explicit/pattern/strict. A :skip
    # or :timeout also fails the run for an explicit model, or for any model when strict (--strict
    # drops the sweep's tolerance for those two); otherwise a pattern model's :skip/:timeout is
    # tolerated as a missing-credentials sweep result. :note never fails.
    def self.exit_code(results, explicit_keys:, strict: false)
      results.any? { |model_result| failing?(model_result, explicit_keys: explicit_keys, strict: strict) } ? 1 : 0
    end

    def self.failing?(model_result, explicit_keys:, strict:)
      capabilities = model_result[:capabilities] || {}
      return true if capabilities.empty?

      explicit = explicit?(model_result, explicit_keys)
      capabilities.each_value.any? { |result| failing_capability?(result, explicit: explicit, strict: strict) }
    end
    private_class_method :failing?

    def self.failing_capability?(result, explicit:, strict:)
      case result[:status]
      when :pass, :note, :consistent
        # :consistent means the provider rejected a claimed-false capability exactly as the
        # manifest declares -- agreement, not a problem, so it never fails the run either.
        false
      when *TOLERABLE_STATUSES
        explicit || strict
      else
        true # :fail, or an unrecognized status, always fails the run
      end
    end
    private_class_method :failing_capability?

    def self.explicit?(model_result, explicit_keys)
      explicit_keys.include?(model_result[:key]) || !!model_result[:explicit]
    end
    private_class_method :explicit?

    # Whether a single capability result (e.g. { status: :pass, detail: "..." }) may be written as a
    # durable smoke observation by `--record`. Only a hard-oracle pass on a capability in
    # Raif::ModelManifest::SmokeObservations::RECORDABLE_POSITIVE_CAPABILITIES qualifies: a SKIP
    # (missing credentials), TIMEOUT (a batch job that never finished), FAIL, NOTE, or CONSISTENT
    # (the provider rejected a claimed-false capability exactly as the manifest declares) is never a
    # completed positive verification, and a result explicitly tagged recordable: false (e.g. the
    # structured_outputs JSON-tool fallback) is not trustworthy evidence of the claimed capability
    # even though its status is :pass.
    def self.recordable?(capability, result)
      Raif::ModelManifest::SmokeObservations::RECORDABLE_POSITIVE_CAPABILITIES.include?(capability.to_sym) &&
        result[:status] == :pass &&
        result.fetch(:recordable, true)
    end
  end
end
