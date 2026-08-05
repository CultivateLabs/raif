# frozen_string_literal: true

module Raif
  module Evals
    # Shared by the run summary and evals:compare, which have to agree on what a mean is
    # before two runs can be ranked against each other.
    module Statistics
      BOOTSTRAP_RESAMPLES = 1000

      # A fixed seed, not a random one: a confidence interval that moves when nothing else
      # did makes two comparisons of the same numbers disagree, which is worse than having
      # no interval at all.
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
        # were, not a sample drawn from a larger set of runs.
        #
        # One value has no spread to report. Returning 0.0 for it reads as "measured, and
        # it does not vary" in a summary a human uses to decide whether a difference is
        # real, when what happened is that nothing was measured.
        def stddev(values)
          return if values.length < 2

          m = mean(values)
          Math.sqrt(values.sum { |value| (value - m)**2 } / values.length.to_f)
        end

        # Percentile bootstrap over whatever unit is passed in. Callers pass per-case means
        # for a dataset eval, so the interval reflects variation between inputs rather than
        # between repeats of the same input.
        # Resampling one value can only ever draw that value, so the interval it produces
        # is zero-width - a 95% confidence claim built from a single observation. Callers
        # get nil and omit the interval instead.
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
