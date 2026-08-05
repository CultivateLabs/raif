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
    it "computes the population standard deviation" do
      expect(described_class.stddev([5, 4, 4, 5, 4, 4])).to be_within(0.0001).of(0.4714)
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
end
