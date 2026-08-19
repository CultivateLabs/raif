# frozen_string_literal: true

# Decides the process exit code for a bin/smoke run, and whether a single
# capability result is trustworthy enough for `--record` to write back into
# the manifest as a verification.
module Smoke
  module Policy
    FAILING_STATUSES = %i[fail timeout].freeze
    RECORDABLE_STATUSES = %i[pass fail note].freeze

    # results - Array of model_result hashes: { key:, explicit:, capabilities: { name => { status:, detail: } } }.
    # explicit_keys - selector strings the caller named directly (Smoke::Selection.resolve's :explicit_keys);
    #   a model_result counts as explicit when its key is in this list or its own :explicit flag is set.
    #
    # Returns 1 when an explicit model has any capability result of :fail, :timeout, or :skip, or ran no
    # checks at all (an empty capabilities hash - an unexecuted required check); or when strict is true and
    # any model, explicit or pattern, has :fail, :timeout, or ran no checks. A pattern model's :skip never
    # fails the run, strict or not, and :note never fails the run for any model.
    def self.exit_code(results, explicit_keys:, strict: false)
      results.any? { |model_result| failing?(model_result, explicit_keys: explicit_keys, strict: strict) } ? 1 : 0
    end

    def self.failing?(model_result, explicit_keys:, strict:)
      explicit = explicit?(model_result, explicit_keys)
      return false unless explicit || strict

      capabilities = model_result[:capabilities] || {}
      return true if capabilities.empty? # an unexecuted required check

      capabilities.each_value.any? { |result| failing_capability?(result, explicit: explicit) }
    end
    private_class_method :failing?

    def self.failing_capability?(result, explicit:)
      status = result[:status]
      return false if status == :note
      return true if FAILING_STATUSES.include?(status)

      # Pattern selections tolerate credential skips; only an explicit selection's own skip fails the run.
      status == :skip && explicit
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
