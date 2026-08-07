# frozen_string_literal: true

module Raif
  module Evals
    # Shared by the run summary and evals:compare, which have to agree on what a mean is
    # before two runs can be ranked against each other.
    module Statistics
      BOOTSTRAP_RESAMPLES = 1000

      # Fixed seed so the interval is stable: two comparisons of the same numbers must not
      # disagree just because the resampling drew differently.
      BOOTSTRAP_SEED = 20260804

      class << self
        def mean(values)
          return if values.empty?

          values.sum.to_f / values.length
        end

        def median(values)
          return if values.empty?

          sorted = values.sort
          middle = sorted.length / 2

          if sorted.length.odd?
            sorted[middle].to_f
          else
            (sorted[middle - 1] + sorted[middle]) / 2.0
          end
        end

        # Population rather than sample standard deviation: these are all the runs there
        # were, not a sample of a larger set. Returns nil rather than 0.0 for a single
        # value, since 0.0 would read as "measured, doesn't vary" when nothing was measured.
        def stddev(values)
          return if values.length < 2

          m = mean(values)
          Math.sqrt(values.sum { |value| (value - m)**2 } / values.length.to_f)
        end

        # Percentile bootstrap over whatever unit is passed in. Callers pass per-case means
        # for a dataset eval, so the interval reflects variation between inputs rather than
        # between repeats of one input. nil for a single value, which can only resample to
        # itself - a zero-width "95% confidence" interval.
        def bootstrap_ci95(values)
          return if values.length < 2

          random = Random.new(BOOTSTRAP_SEED)
          size = values.length

          means = Array.new(BOOTSTRAP_RESAMPLES) do
            Array.new(size) { values[random.rand(size)] }.sum.to_f / size
          end.sort

          [percentile(means, 0.025), percentile(means, 0.975)]
        end

      private

        def percentile(sorted, fraction)
          index = ((sorted.length - 1) * fraction).round
          sorted[index]
        end
      end
    end
  end
end
