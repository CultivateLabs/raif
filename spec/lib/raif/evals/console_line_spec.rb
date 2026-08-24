# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Evals::ConsoleLine do
  describe ".truncate_description" do
    it "leaves a description that already fits alone" do
      expect(described_class.truncate_description("LLM judge score (clarity): >= 4")).to eq("LLM judge score (clarity): >= 4")
    end

    it "truncates a description longer than the limit and marks it as cut" do
      description = "The text does NOT set an analytic agenda for the reader: it does not tell the reader what questions to investigate"
      truncated = described_class.truncate_description(description)

      expect(truncated.length).to be <= described_class::MAX_DESCRIPTION_LENGTH + 3
      expect(truncated).to end_with("...")
      expect(description).to start_with(truncated.delete_suffix("..."))
    end

    it "does not leave a dangling space before the ellipsis" do
      expect(described_class.truncate_description("#{"a" * 99} bbbb", limit: 100)).to eq("#{"a" * 99}...")
    end

    it "honours an explicit limit" do
      expect(described_class.truncate_description("abcdefghij", limit: 4)).to eq("abcd...")
    end

    it "handles a nil description" do
      expect(described_class.truncate_description(nil)).to eq("")
    end
  end
end
