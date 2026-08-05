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
        def stddev(values)
          return if values.empty?

          m = mean(values)
          Math.sqrt(values.sum { |value| (value - m)**2 } / values.length.to_f)
        end

        # Percentile bootstrap over whatever unit is passed in. Callers pass per-case means
        # for a dataset eval, so the interval reflects variation between inputs rather than
        # between repeats of the same input.
        def bootstrap_ci95(values)
          return if values.empty?
          return [values.first.to_f, values.first.to_f] if values.length == 1

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
