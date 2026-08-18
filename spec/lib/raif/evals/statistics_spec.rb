# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Evals::Statistics do
  describe ".mean" do
    it "averages the values" do
      expect(described_class.mean([4, 5, 4, 5, 4, 4])).to be_within(0.0001).of(4.3333)
    end

    it "returns nil for no values" do
      expect(described_class.mean([])).to be_nil
    end
  end

  describe ".median" do
    it "takes the middle value for an odd count" do
      expect(described_class.median([5, 1, 3])).to eq(3.0)
    end

    it "averages the middle two for an even count" do
      expect(described_class.median([1, 2, 3, 4])).to eq(2.5)
    end
  end

  describe ".stddev" do
    it "computes the sample standard deviation" do
      expect(described_class.stddev([5, 4, 4, 5, 4, 4])).to be_within(0.0001).of(0.5164)
    end

    # These are draws from the model's output distribution, not the whole of it, and dividing by n
    # understates the spread worst at exactly the sizes an eval run produces. Understating it
    # defeats the only reason the figure is printed.
    it "divides by n-1 rather than n" do
      values = [2.0, 4.0]
      population = Math.sqrt(1.0)

      expect(described_class.stddev(values)).to be_within(0.0001).of(Math.sqrt(2.0))
      expect(described_class.stddev(values)).to be_within(0.0001).of(population * Math.sqrt(2.0))
    end

    it "is zero when every value is the same" do
      expect(described_class.stddev([3, 3, 3])).to eq(0.0)
    end

    # 0.0 would read as "measured, and it does not vary" rather than "not measured".
    it "returns nil for a single observation" do
      expect(described_class.stddev([4.0])).to be_nil
    end

    it "returns nil for no values" do
      expect(described_class.stddev([])).to be_nil
    end
  end

  describe ".bootstrap_ci95" do
    it "brackets the mean" do
      values = [4.0, 4.5, 4.5, 5.0, 3.5, 4.0]
      low, high = described_class.bootstrap_ci95(values)

      expect(low).to be < described_class.mean(values)
      expect(high).to be > described_class.mean(values)
    end

    # A seed that moved between runs would make two comparisons of the same numbers disagree.
    it "is deterministic for the same values" do
      values = [1.0, 2.0, 3.0, 4.0]

      expect(described_class.bootstrap_ci95(values)).to eq(described_class.bootstrap_ci95(values))
    end

    # Resampling one value can only draw that value, so the interval would be zero-width -
    # a 95% confidence claim from a single observation.
    it "returns nil for a single observation" do
      expect(described_class.bootstrap_ci95([4.0])).to be_nil
    end

    it "returns nil for no values" do
      expect(described_class.bootstrap_ci95([])).to be_nil
    end
  end

  # Exact rather than resampled: the gate divides its level by the number of rows it tests, so it
  # asks for p-values further into the tail than 1,000 bootstrap resamples can resolve.
  describe ".sign_test" do
    it "returns nil when no pair moved" do
      expect(described_class.sign_test(worsened: 0, improved: 0)).to be_nil
    end

    # A single pair is the largest p-value the test can produce, which is the right answer to
    # "one case moved, is that evidence" - no.
    it "cannot reach significance on one pair" do
      expect(described_class.sign_test(worsened: 1, improved: 0)).to eq(1.0)
    end

    # Two-sided exact binomial at p=0.5: 2 * C(n,n) / 2**n.
    it "matches the exact binomial tail" do
      expect(described_class.sign_test(worsened: 2, improved: 0)).to eq(0.5)
      expect(described_class.sign_test(worsened: 5, improved: 0)).to eq(0.0625)
      expect(described_class.sign_test(worsened: 6, improved: 0)).to eq(0.03125)
    end

    # 17 of 20 cases worse: 2 * (C(20,17) + C(20,18) + C(20,19) + C(20,20)) / 2**20.
    it "counts the tail rather than only the extreme" do
      expect(described_class.sign_test(worsened: 17, improved: 3)).to be_within(0.000001).of(0.002577)
    end

    it "is symmetric and caps at 1.0" do
      expect(described_class.sign_test(worsened: 3, improved: 7)).to eq(described_class.sign_test(worsened: 7, improved: 3))
      expect(described_class.sign_test(worsened: 10, improved: 10)).to eq(1.0)
    end

    # Ruby Integers are arbitrary precision but the Float they would become is not: the tail of a
    # large binomial overflows long before the ratio it sits in does.
    it "does not overflow on a large number of pairs" do
      p_value = described_class.sign_test(worsened: 700, improved: 0)

      expect(p_value).to be_finite
      expect(p_value).to be > 0
      expect(p_value).to be < 1e-200
      expect(described_class.sign_test(worsened: 350, improved: 350)).to eq(1.0)
    end
  end

  describe ".fisher_exact_p" do
    it "returns nil when a margin is empty" do
      expect(described_class.fisher_exact_p(baseline_passed: 3, baseline_total: 3, candidate_passed: 3, candidate_total: 3)).to be_nil
      expect(described_class.fisher_exact_p(baseline_passed: 0, baseline_total: 0, candidate_passed: 0, candidate_total: 2)).to be_nil
    end

    # One repeat a side is one draw a side, and no test can call that a regression.
    it "cannot reach significance on one observation per side" do
      expect(described_class.fisher_exact_p(baseline_passed: 1, baseline_total: 1, candidate_passed: 0, candidate_total: 1)).to eq(1.0)
    end

    # 5/5 against 0/5 is 2 * (1 / C(10,5)) = 2/252.
    it "matches the exact hypergeometric two-sided tail" do
      expect(described_class.fisher_exact_p(baseline_passed: 5, baseline_total: 5, candidate_passed: 0, candidate_total: 5))
        .to be_within(0.000001).of(0.007937)
      expect(described_class.fisher_exact_p(baseline_passed: 5, baseline_total: 5, candidate_passed: 3, candidate_total: 5))
        .to be_within(0.000001).of(0.444444)
      expect(described_class.fisher_exact_p(baseline_passed: 20, baseline_total: 20, candidate_passed: 10, candidate_total: 20))
        .to be_within(0.000001).of(0.000436)
    end

    it "returns nil rather than raising when a count exceeds its total" do
      expect(described_class.fisher_exact_p(baseline_passed: 4, baseline_total: 2, candidate_passed: 0, candidate_total: 2)).to be_nil
    end
  end
end
