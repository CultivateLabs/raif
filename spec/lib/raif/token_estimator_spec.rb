# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::TokenEstimator do
  describe ".available?" do
    it "returns a boolean matching whether Tiktoken is defined" do
      if defined?(Tiktoken)
        expect(described_class.available?).to be true
      else
        expect(described_class.available?).to be false
      end
    end
  end

  describe ".estimate_tokens" do
    context "when tiktoken_ruby is not installed" do
      before do
        allow(described_class).to receive(:available?).and_return(false)
      end

      it "returns nil" do
        expect(described_class.estimate_tokens("Hello world")).to be_nil
      end
    end

    context "when tiktoken_ruby is installed" do
      before do
        skip "tiktoken_ruby not installed" unless described_class.available?
      end

      it "returns a positive integer for non-empty text" do
        result = described_class.estimate_tokens("Hello world, this is a test.")
        expect(result).to be_a(Integer)
        expect(result).to be > 0
      end

      it "sums tokens across multiple texts" do
        single = described_class.estimate_tokens("Hello world")
        combined = described_class.estimate_tokens("Hello", "world")
        expect(combined).to be > 0
        expect(single).to be > 0
      end

      it "handles nil texts gracefully" do
        result = described_class.estimate_tokens(nil, "Hello world", nil)
        expect(result).to be_a(Integer)
        expect(result).to be > 0
      end

      it "returns 0 for all nil texts" do
        expect(described_class.estimate_tokens(nil, nil)).to eq(0)
      end
    end
  end
end
