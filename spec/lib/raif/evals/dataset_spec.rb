# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Evals::Dataset do
  let(:rows) do
    [
      { id: "alpha", input: { "topic" => "a" }, expected: { "subject" => "a" } },
      { id: "beta", input: { "topic" => "b" } },
      { id: "gamma", input: { "topic" => "c" } }
    ]
  end

  describe "#initialize" do
    it "builds frozen cases exposing id, input, and expected" do
      dataset = described_class.new(name: :topics, cases: rows)

      expect(dataset.size).to eq(3)
      expect(dataset.cases.map(&:id)).to eq(["alpha", "beta", "gamma"])
      expect(dataset.cases.first.input).to eq("topic" => "a")
      expect(dataset.cases.first.expected).to eq("subject" => "a")
      expect(dataset.cases.second.expected).to be_nil
      expect(dataset.cases.first).to be_frozen
    end

    it "accepts string keys, as JSON-sourced rows have" do
      dataset = described_class.new(name: :topics, cases: [{ "id" => "alpha", "input" => { "topic" => "a" }, "expected" => { "s" => 1 } }])

      expect(dataset.cases.first.id).to eq("alpha")
      expect(dataset.cases.first.input).to eq("topic" => "a")
      expect(dataset.cases.first.expected).to eq("s" => 1)
    end

    # A binary-classification case can legitimately expect `false`; a `||` fallback would
    # turn it into nil, silently changing what the case asserts.
    it "preserves an explicit false expected value" do
      symbol_keyed = described_class.new(name: :flags, cases: [{ id: "negative", input: { "topic" => "a" }, expected: false }])
      string_keyed = described_class.new(name: :flags, cases: [{ "id" => "negative", "input" => { "topic" => "a" }, "expected" => false }])

      expect(symbol_keyed.cases.first.expected).to be(false)
      expect(string_keyed.cases.first.expected).to be(false)
    end

    it "coerces non-string ids" do
      dataset = described_class.new(name: :topics, cases: [{ id: 7, input: {} }])

      expect(dataset.cases.first.id).to eq("7")
    end

    it "raises when a case has no id" do
      expect do
        described_class.new(name: :topics, cases: [{ input: { "topic" => "a" } }])
      end.to raise_error(ArgumentError, /case at index 0 is missing an :id/)
    end

    it "raises when a case has a blank id" do
      expect do
        described_class.new(name: :topics, cases: [{ id: "  ", input: {} }])
      end.to raise_error(ArgumentError, /missing an :id/)
    end

    it "raises when a case has no input" do
      expect do
        described_class.new(name: :topics, cases: [{ id: "alpha" }])
      end.to raise_error(ArgumentError, /case "alpha" is missing an :input/)
    end

    # Two cases that cannot be told apart produce a mean that silently cannot be diffed.
    it "raises when ids are duplicated" do
      expect do
        described_class.new(name: :topics, cases: rows + [{ id: "alpha", input: {} }])
      end.to raise_error(ArgumentError, /duplicate case ids: "alpha"/)
    end

    it "raises when the block did not return an array" do
      expect do
        described_class.new(name: :topics, cases: { id: "alpha", input: {} })
      end.to raise_error(ArgumentError, /returned Hash; a dataset block must return an array/)
    end

    it "raises when a case is not a hash" do
      expect do
        described_class.new(name: :topics, cases: ["alpha"])
      end.to raise_error(ArgumentError, /case at index 0 is String/)
    end
  end

  describe "#select_cases" do
    let(:dataset) { described_class.new(name: :topics, cases: rows) }

    it "returns every case by default" do
      expect(dataset.select_cases.map(&:id)).to eq(["alpha", "beta", "gamma"])
    end

    it "filters to the named ids" do
      expect(dataset.only(["gamma", "alpha"]).map(&:id)).to eq(["alpha", "gamma"])
    end

    # --cases is run-wide, so ids belonging to another eval set's dataset filter this one to
    # nothing rather than raising. The run errors if nothing matched anywhere.
    it "returns nothing when no id matches" do
      expect(dataset.only(["nope"])).to eq([])
    end

    it "samples deterministically under a seed, keeping dataset order" do
      first = dataset.sample(2, seed: 42).map(&:id)
      second = dataset.sample(2, seed: 42).map(&:id)

      expect(first.size).to eq(2)
      expect(first).to eq(second)
      expect(first).to eq(first.sort_by { |id| ["alpha", "beta", "gamma"].index(id) })
    end

    # #digest ignores row order, so a resume is allowed across a reordered file. If the draw
    # followed row order the same logged seed would resolve to a different sample, and the results
    # file would end up holding two unrelated samples under one seed.
    it "draws the same cases under one seed however the rows are ordered" do
      reordered = described_class.new(name: :topics, cases: rows.reverse)

      expect(reordered.digest).to eq(dataset.digest)
      expect(reordered.sample(2, seed: 42).map(&:id).sort).to eq(dataset.sample(2, seed: 42).map(&:id).sort)
    end

    it "draws a different sample under a different seed" do
      samples = (1..25).map { |seed| dataset.sample(2, seed: seed).map(&:id) }.uniq

      expect(samples.size).to be > 1
    end

    it "returns every case when the sample is at least the dataset size" do
      expect(dataset.sample(3, seed: 1).map(&:id)).to eq(["alpha", "beta", "gamma"])
      expect(dataset.sample(9, seed: 1).map(&:id)).to eq(["alpha", "beta", "gamma"])
    end

    it "applies the id filter before sampling" do
      selected = dataset.select_cases(ids: ["alpha", "beta"], sample: 1, seed: 3)

      expect(selected.size).to eq(1)
      expect(["alpha", "beta"]).to include(selected.first.id)
    end
  end

  describe "#digest" do
    it "is stable across two datasets holding the same cases" do
      expect(described_class.new(name: :topics, cases: rows).digest).to eq(described_class.new(name: :topics, cases: rows).digest)
    end

    # The digest tracks what the cases are, not how the file is arranged, so reformatting a dataset
    # must not read as a changed dataset.
    it "ignores the order of the rows and of the keys within them" do
      reordered = [
        { input: { "topic" => "c" }, id: "gamma" },
        { id: "alpha", expected: { "subject" => "a" }, input: { "topic" => "a" } },
        { id: "beta", input: { "topic" => "b" } }
      ]

      expect(described_class.new(name: :topics, cases: reordered).digest).to eq(described_class.new(name: :topics, cases: rows).digest)
    end

    it "is the same for symbol keys and the string keys a JSONL file produces" do
      symbol_keyed = described_class.new(name: :topics, cases: [{ id: "alpha", input: { topic: "a" } }])
      string_keyed = described_class.new(name: :topics, cases: [{ "id" => "alpha", "input" => { "topic" => "a" } }])

      expect(symbol_keyed.digest).to eq(string_keyed.digest)
    end

    # The whole point: an edited case has to be visible to a later reader of the results file.
    it "changes when an input changes" do
      edited = rows.map { |row| row[:id] == "beta" ? row.merge(input: { "topic" => "edited" }) : row }

      expect(described_class.new(name: :topics, cases: edited).digest).not_to eq(described_class.new(name: :topics, cases: rows).digest)
    end

    it "changes when an expected value changes" do
      edited = rows.map { |row| row[:id] == "alpha" ? row.merge(expected: { "subject" => "z" }) : row }

      expect(described_class.new(name: :topics, cases: edited).digest).not_to eq(described_class.new(name: :topics, cases: rows).digest)
    end

    it "changes when a case is added" do
      widened = rows + [{ id: "delta", input: { "topic" => "d" } }]

      expect(described_class.new(name: :topics, cases: widened).digest).not_to eq(described_class.new(name: :topics, cases: rows).digest)
    end

    it "is prefixed with the hash it used" do
      expect(described_class.new(name: :topics, cases: rows).digest).to match(/\Asha256:[0-9a-f]{64}\z/)
    end
  end

  describe Raif::Evals::EvalCase do
    it "reads through to input" do
      eval_case = described_class.new(id: "alpha", input: { "topic" => "a" })

      expect(eval_case["topic"]).to eq("a")
      expect(eval_case.to_h).to eq(id: "alpha", input: { "topic" => "a" })
    end
  end
end
