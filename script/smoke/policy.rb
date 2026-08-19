# frozen_string_literal: true

# Decides the process exit code for a bin/smoke run, and whether a single
# capability result is trustworthy enough for `--record` to write back into
# the manifest as a verification.
module Smoke
  module Policy
    TOLERABLE_STATUSES = %i[skip timeout].freeze
    RECORDABLE_STATUSES = %i[pass fail note].freeze

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
      return true if capabilities.empty? # an unexecuted required check, never tolerated

      explicit = explicit?(model_result, explicit_keys)
      capabilities.each_value.any? { |result| failing_capability?(result, explicit: explicit, strict: strict) }
    end
    private_class_method :failing?

    def self.failing_capability?(result, explicit:, strict:)
      case result[:status]
      when :pass, :note
        false
      when *TOLERABLE_STATUSES
        # Tolerated only for a non-explicit (pattern) model outside --strict; --strict drops the
        # tolerance so a full sweep also catches a stuck or uncredentialed provider.
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

    # Whether a single capability result (e.g. { status: :pass, detail: "..." }) may be written back to
    # the manifest by `--record`. explicit_keys exists only for interface symmetry with exit_code; the
    # rule ignores it, since a SKIP (missing credentials) or TIMEOUT (a batch job that never finished)
    # is never a completed verification, explicit selection or not, and recording one would let a
    # skipped or incomplete check masquerade as a verified capability.
    def self.recordable?(model_result, explicit_keys: [])
      RECORDABLE_STATUSES.include?(model_result[:status])
    end
  end
end
