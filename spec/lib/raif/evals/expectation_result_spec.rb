# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Evals::ExpectationResult do
  describe "#initialize" do
    it "creates an expectation result with passed status" do
      result = described_class.new(description: "test passes", status: :passed)

      expect(result.description).to eq("test passes")
      expect(result.status).to eq(:passed)
      expect(result.error).to be_nil
    end

    it "creates an expectation result with error" do
      error = StandardError.new("Something went wrong")
      result = described_class.new(description: "test errors", status: :error, error: error)

      expect(result.description).to eq("test errors")
      expect(result.status).to eq(:error)
      expect(result.error).to eq(error)
    end
  end

  describe "#passed?" do
    it "returns true for passed status" do
      result = described_class.new(description: "test", status: :passed)
      expect(result.passed?).to be true
    end

    it "returns false for failed status" do
      result = described_class.new(description: "test", status: :failed)
      expect(result.passed?).to be false
    end
  end

  describe "#failed?" do
    it "returns true for failed status" do
      result = described_class.new(description: "test", status: :failed)
      expect(result.failed?).to be true
    end

    it "returns false for passed status" do
      result = described_class.new(description: "test", status: :passed)
      expect(result.failed?).to be false
    end
  end

  describe "#error?" do
    it "returns true for error status" do
      result = described_class.new(description: "test", status: :error)
      expect(result.error?).to be true
    end

    it "returns false for passed status" do
      result = described_class.new(description: "test", status: :passed)
      expect(result.error?).to be false
    end
  end

  describe "#to_h" do
    it "converts to hash without error" do
      result = described_class.new(description: "test passes", status: :passed)

      expect(result.to_h).to eq({
        description: "test passes",
        status: :passed
      })
    end

    it "converts to hash with error message" do
      error = StandardError.new("Something went wrong")
      result = described_class.new(description: "test errors", status: :error, error: error)

      expect(result.to_h).to eq({
        description: "test errors",
        status: :error,
        error: "Something went wrong"
      })
    end
  end
end
