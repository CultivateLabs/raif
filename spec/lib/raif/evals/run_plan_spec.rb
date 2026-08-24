# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Evals::RunPlan do
  let(:keys) do
    [
      ["MySet#first-abc123", nil, nil],
      ["MySet#second-def456", "atom", 1],
      ["MySet#second-def456", "atom", 2]
    ]
  end

  let(:plan) { described_class.new(keys: keys) }

  describe "#outstanding" do
    it "is the planned keys no result has been recorded for, in plan order" do
      recorded = [Raif::Evals::RunLog.key(eval_id: "MySet#second-def456", case_id: "atom", run_index: 1)]

      expect(plan.outstanding(recorded)).to eq([keys.first, keys.last])
    end

    it "is empty once every planned key is recorded" do
      expect(plan.outstanding(keys)).to eq([])
    end

    # A key read back out of a log has been through JSON, which has no symbols and no tuples.
    it "matches a key that came back off disk" do
      round_tripped = JSON.parse(JSON.generate(keys))

      expect(plan.outstanding(round_tripped)).to eq([])
    end
  end

  describe ".from_h" do
    it "reads a plan it wrote" do
      restored = described_class.from_h(JSON.parse(JSON.generate(plan.to_h), symbolize_names: true))

      expect(restored.keys).to eq(keys)
    end

    it "is nil for a version it does not know" do
      expect(described_class.from_h({ version: described_class::VERSION + 1, keys: keys })).to be_nil
    end

    it "is nil for anything that is not a plan" do
      expect(described_class.from_h(nil)).to be_nil
      expect(described_class.from_h({ keys: keys })).to be_nil
    end
  end

  describe "#additions" do
    it "is the keys of another plan this one does not hold, in that plan's order" do
      other = described_class.new(keys: [["MySet#third-ghi789", nil, nil], keys.first])

      expect(plan.additions(other)).to eq([["MySet#third-ghi789", nil, nil]])
    end

    it "is empty for a plan this one already covers" do
      expect(plan.additions(described_class.new(keys: [keys.last]))).to eq([])
    end
  end

  it "holds each key once, however many times it is given" do
    expect(described_class.new(keys: keys + keys).size).to eq(3)
  end
end
