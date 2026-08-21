# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Evals::ScoreResult do
  it "coerces the value to a float and serializes the scale as a string" do
    result = described_class.new(name: :clarity, value: 4, scale: 1..5, min: 4)

    expect(result.to_h).to eq(
      name: "clarity",
      value: 4.0,
      scale: "1..5",
      higher_is_better: true,
      min: 4,
      passed: true
    )
  end

  # to_f would make all of these 0.0 without complaint. Against a max: ceiling that reads as the
  # best possible measurement and passes the gate, which is the worst way for a metric to be wrong.
  [nil, "not a number", "4", [], :four].each do |bad|
    it "refuses a non-numeric value (#{bad.inspect})" do
      expect { described_class.new(name: "elapsed_ms", value: bad, max: 5000, higher_is_better: false) }
        .to raise_error(ArgumentError, /"elapsed_ms" was given #{Regexp.escape(bad.inspect)}.*must be numeric/)
    end
  end

  it "accepts every numeric kind, including a BigDecimal and a Rational" do
    expect(described_class.new(name: "a", value: 4).value).to eq(4.0)
    expect(described_class.new(name: "b", value: 4.5).value).to eq(4.5)
    expect(described_class.new(name: "c", value: BigDecimal("4.5")).value).to eq(4.5)
    expect(described_class.new(name: "d", value: Rational(9, 2)).value).to eq(4.5)
  end

  it "omits the gate keys when there is neither a min nor a max" do
    result = described_class.new(name: "summary_word_count", value: 284)

    expect(result.gated?).to be false
    expect(result.to_h).to eq(name: "summary_word_count", value: 284.0, higher_is_better: true)
  end

  it "keeps higher_is_better: false in the payload" do
    result = described_class.new(name: "elapsed_ms", value: 812, higher_is_better: false)

    expect(result.to_h).to eq(name: "elapsed_ms", value: 812.0, higher_is_better: false)
  end

  it "serializes a max gate" do
    result = described_class.new(name: "elapsed_ms", value: 812, max: 500, higher_is_better: false)

    expect(result.to_h).to eq(name: "elapsed_ms", value: 812.0, higher_is_better: false, max: 500, passed: false)
  end

  describe "#passed?" do
    it "passes at the minimum" do
      expect(described_class.new(name: "clarity", value: 4, min: 4).passed?).to be true
    end

    it "fails below the minimum" do
      expect(described_class.new(name: "clarity", value: 3.5, min: 4).passed?).to be false
    end

    it "passes at the maximum" do
      expect(described_class.new(name: "elapsed_ms", value: 500, max: 500).passed?).to be true
    end

    it "fails above the maximum" do
      expect(described_class.new(name: "elapsed_ms", value: 501, max: 500).passed?).to be false
    end

    it "requires both bounds when both are given" do
      expect(described_class.new(name: "words", value: 250, min: 100, max: 1000).passed?).to be true
      expect(described_class.new(name: "words", value: 50, min: 100, max: 1000).passed?).to be false
      expect(described_class.new(name: "words", value: 1200, min: 100, max: 1000).passed?).to be false
    end

    it "is true for an ungated score" do
      expect(described_class.new(name: "clarity", value: 1).passed?).to be true
    end
  end

  describe "#gate_description" do
    it "reads as the comparison it performs" do
      expect(described_class.new(name: "clarity", value: 4, min: 4).gate_description).to eq("clarity score >= 4")
      expect(described_class.new(name: "elapsed_ms", value: 4, max: 500).gate_description).to eq("elapsed_ms score <= 500")
      expect(described_class.new(name: "words", value: 4, min: 100, max: 1000).gate_description).to eq("words score >= 100 and <= 1000")
    end
  end

  describe "#formatted_value" do
    it "drops the decimal for whole numbers" do
      expect(described_class.new(name: "clarity", value: 4.0).formatted_value).to eq("4")
    end

    it "keeps the decimal otherwise" do
      expect(described_class.new(name: "clarity", value: 4.25).formatted_value).to eq("4.25")
    end
  end
end
