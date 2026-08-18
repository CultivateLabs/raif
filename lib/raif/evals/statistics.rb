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

        # Sample standard deviation - divided by n-1, not n. These values are draws from the
        # model's output distribution, not the whole of it: that is what --repeat exists to
        # sample, and the reason the figure is printed at all is to stop a reader over-reading a
        # difference in means, which is an inference about the distribution behind them.
        # Dividing by n understates the spread by 0.71x at n=2 and 0.89x at n=5, which is exactly
        # the range these runs live in, and understating it is the one error that defeats the
        # purpose of showing it.
        #
        # Bessel's correction makes the variance unbiased, not the standard deviation - the sqrt
        # of an unbiased variance is still biased low (about 0.80x at n=2). It reduces the bias
        # rather than removing it; ask #bootstrap_ci95 for an interval that does not lean on the
        # normal assumption a closed-form correction would need.
        #
        # Returns nil rather than 0.0 for a single value, since 0.0 would read as "measured,
        # doesn't vary" when nothing was measured.
        def stddev(values)
          return if values.length < 2

          m = mean(values)
          Math.sqrt(values.sum { |value| (value - m)**2 } / (values.length - 1).to_f)
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

        # Two-sided sign test over matched pairs: of the pairs that moved, how surprising is it
        # that this many moved the same way, if the two runs were interchangeable.
        #
        # Exact rather than resampled, which matters here for two reasons. Eval runs produce a
        # handful of pairs, where a bootstrap's normal-ish assumptions are worst, and the gate
        # divides its threshold by the number of rows it tests, so it asks for p-values well into
        # the tail - further than the 1,000 resamples #bootstrap_ci95 draws can resolve.
        #
        # Ties are excluded rather than split, the standard treatment: a case that did not move
        # is evidence for neither side. That also means the test reads only the direction each
        # pair moved, not how far, which is deliberate - magnitude is what the caller's
        # effect-size threshold is for, and keeping the two separate stops a single wild case
        # from carrying a verdict.
        #
        # @return [Float, nil] two-sided p-value, or nil when no pair moved
        def sign_test(worsened:, improved:)
          pairs = worsened + improved
          return if pairs.zero?

          extreme = [worsened, improved].max
          tail = (extreme..pairs).sum { |k| binomial_coefficient(pairs, k) }

          # Rational until the last step: the tail of a large binomial overflows Float long
          # before the ratio it appears in does.
          [(Rational(2 * tail, 2**pairs)).to_f, 1.0].min
        end

        # Two-sided Fisher exact test on a 2x2 table, for two runs whose observations cannot be
        # paired - a non-dataset eval, where the only unit is the repeat, and repeat 3 of one run
        # is not the counterpart of repeat 3 of the other.
        #
        # Exact for the same reason as #sign_test, and doubly so here: at the repeat counts these
        # runs use, the smallest reachable p-value is a property of the table's margins, and an
        # approximation would invent significance the counts cannot support.
        #
        # @return [Float, nil] two-sided p-value, or nil when a margin is empty
        def fisher_exact_p(baseline_passed:, baseline_total:, candidate_passed:, candidate_total:)
          baseline_failed = baseline_total - baseline_passed
          candidate_failed = candidate_total - candidate_passed
          passed = baseline_passed + candidate_passed
          failed = baseline_failed + candidate_failed

          return if baseline_total.zero? || candidate_total.zero? || passed.zero? || failed.zero?
          return if [baseline_failed, candidate_failed].any?(&:negative?)

          observed = hypergeometric(baseline_total, candidate_total, passed, baseline_passed)

          # Every table with these margins, summing the ones no more likely than what was seen.
          low = [0, passed - candidate_total].max
          high = [passed, baseline_total].min

          total = (low..high).sum do |k|
            probability = hypergeometric(baseline_total, candidate_total, passed, k)
            probability <= observed ? probability : 0
          end

          [total.to_f, 1.0].min
        end

      private

        # Rational, so the comparison against the observed table is exact and a large table
        # cannot overflow its way into a wrong answer.
        def hypergeometric(row1, row2, col1, k)
          Rational(
            binomial_coefficient(row1, k) * binomial_coefficient(row2, col1 - k),
            binomial_coefficient(row1 + row2, col1)
          )
        end

        def binomial_coefficient(n, k)
          return 0 if k.negative? || k > n

          k = [k, n - k].min
          (1..k).reduce(1) { |product, i| product * (n - k + i) / i }
        end

        def percentile(sorted, fraction)
          index = ((sorted.length - 1) * fraction).round
          sorted[index]
        end
      end
    end
  end
end
