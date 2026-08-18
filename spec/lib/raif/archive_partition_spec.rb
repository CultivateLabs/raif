# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::ArchivePartition do
  describe ".for" do
    it "normalizes integer and string inputs of the same value identically" do
      from_integer = described_class.for(42)
      from_string = described_class.for("42")

      expect(from_integer.value).to eq("42")
      expect(from_string.value).to eq("42")
      expect(from_integer.token).to eq(from_string.token)
      expect(from_integer.storage_prefix).to eq(from_string.storage_prefix)
    end

    it "normalizes with to_s exactly, without stripping" do
      expect(described_class.for(" 42 ").value).to eq(" 42 ")
    end

    it "rejects nil and values that normalize to blank" do
      expect { described_class.for(nil) }.to raise_error(ArgumentError, /blank/)
      expect { described_class.for("") }.to raise_error(ArgumentError, /blank/)
      expect { described_class.for("   ") }.to raise_error(ArgumentError, /blank/)
    end

    it "derives the token as the SHA-256 hex digest of the normalized value" do
      partition = described_class.for(42)

      expect(partition.token).to eq(Digest::SHA256.hexdigest("42"))
    end

    it "derives the storage prefix from the token, above the resource type" do
      partition = described_class.for(42)

      expect(partition.storage_prefix).to eq("raif-archives/partitions/#{Digest::SHA256.hexdigest("42")}/")
    end

    it "is not ungrouped for a real value" do
      expect(described_class.for(42).ungrouped?).to be(false)
    end

    it "hashes a real value that normalizes to the string _ungrouped like any other value" do
      partition = described_class.for("_ungrouped")

      expect(partition.ungrouped?).to be(false)
      expect(partition.value).to eq("_ungrouped")
      expect(partition.token).to eq(Digest::SHA256.hexdigest("_ungrouped"))
      expect(partition.storage_prefix).not_to include("/_ungrouped/")
    end

    it "returns the reserved ungrouped partition for the UNGROUPED sentinel" do
      expect(described_class.for(described_class::UNGROUPED).ungrouped?).to be(true)
    end
  end

  describe ".ungrouped" do
    let(:partition) { described_class.ungrouped }

    it "is ungrouped with a nil value (stored as NULL on Raif::Archive)" do
      expect(partition.ungrouped?).to be(true)
      expect(partition.value).to be_nil
    end

    it "uses the reserved _ungrouped storage segment instead of a hash token" do
      expect(partition.token).to eq("_ungrouped")
      expect(partition.storage_prefix).to eq("raif-archives/partitions/_ungrouped/")
    end
  end
end
