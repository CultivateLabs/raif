# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Evals::EvalSets::Matchers do
  let(:test_eval_set_class) do
    Class.new(Raif::Evals::EvalSet) do
      def self.name
        "TestEvalSet"
      end

      def initialize(output: $stdout)
        super

        @current_eval_result = Raif::Evals::EvalResult.new(description: "test description")
      end
    end
  end

  let(:output) { StringIO.new }
  let(:eval_set) { test_eval_set_class.new(output: output) }

  describe "#expect_exact_match" do
    it "passes on a match, and records both sides" do
      result = eval_set.expect_exact_match("Emissions", "emissions")

      expect(result).to be_a(Raif::Evals::ExpectationResult)
      expect(result.passed?).to eq(true)
      expect(result.description).to eq("exact match")
      expect(result.metadata).to eq({ actual: "Emissions", expected: "emissions" })
    end

    it "normalizes case and surrounding whitespace by default" do
      expect(eval_set.expect_exact_match("  Yes\n", "yes").passed?).to eq(true)
    end

    it "does not normalize when asked not to" do
      expect(eval_set.expect_exact_match("  Yes\n", "yes", ignore_case: false, strip: false).passed?).to eq(false)
      expect(eval_set.expect_exact_match("Yes", "yes", ignore_case: false).passed?).to eq(false)
    end

    it "compares non-strings by value rather than through to_s" do
      expect(eval_set.expect_exact_match(false, false).passed?).to eq(true)
      expect(eval_set.expect_exact_match(42, 42).passed?).to eq(true)
      expect(eval_set.expect_exact_match(["a", "b"], ["a", "b"]).passed?).to eq(true)
      expect(eval_set.expect_exact_match("42", 42).passed?).to eq(false)
    end

    it "accepts a custom label and extra metadata" do
      result = eval_set.expect_exact_match("a", "b", label: "answers the question", result_metadata: { case_id: "c1" })

      expect(result.description).to eq("answers the question")
      expect(result.metadata).to eq({ case_id: "c1", actual: "a", expected: "b" })
    end

    it "truncates long values in metadata" do
      result = eval_set.expect_exact_match("x" * 600, "y")

      expect(result.metadata[:actual].length).to eq(Raif::Evals::EvalSets::Matchers::MAX_METADATA_LENGTH + 3)
      expect(result.metadata[:actual]).to end_with("...")
    end
  end

  describe "#expect_includes" do
    it "passes when the text appears" do
      result = eval_set.expect_includes("The 2026 Emissions Outlook", "emissions")

      expect(result.passed?).to eq(true)
      expect(result.description).to eq("includes expected text")
      expect(result.metadata).to eq({ actual: "The 2026 Emissions Outlook", expected: "emissions", missing: [] })
    end

    it "requires every member of an array and reports the ones that are missing" do
      result = eval_set.expect_includes("revenue grew", ["revenue", "margin", "guidance"])

      expect(result.passed?).to eq(false)
      expect(result.metadata[:missing]).to eq(["margin", "guidance"])
    end

    it "honors ignore_case" do
      expect(eval_set.expect_includes("Revenue", "revenue", ignore_case: false).passed?).to eq(false)
      expect(eval_set.expect_includes("Revenue", "revenue").passed?).to eq(true)
    end

    it "fails rather than passes vacuously on an empty expectation" do
      expect(eval_set.expect_includes("anything", []).passed?).to eq(false)
    end

    it "reads non-string values as text" do
      expect(eval_set.expect_includes({ "subject" => "emissions" }, "emissions").passed?).to eq(true)
    end
  end

  describe "#expect_matches" do
    it "passes on a regexp match" do
      result = eval_set.expect_matches("AB-1234", /\A[A-Z]{2}-\d{4}\z/)

      expect(result.passed?).to eq(true)
      expect(result.description).to eq("matches expected pattern")
      expect(result.metadata[:pattern]).to eq("/\\A[A-Z]{2}-\\d{4}\\z/")
    end

    it "compiles a string pattern, so a dataset row can carry one" do
      expect(eval_set.expect_matches("AB-1234", "\\d{4}").passed?).to eq(true)
      expect(eval_set.expect_matches("AB-12", "\\d{4}").passed?).to eq(false)
    end
  end

  describe "#expect_within" do
    it "passes inside an absolute tolerance" do
      result = eval_set.expect_within(42.4, 42.0, delta: 0.5)

      expect(result.passed?).to eq(true)
      expect(result.description).to eq("within 0.5 of expected")
      expect(result.metadata.except(:difference)).to eq({ actual: "42.4", expected: "42.0", tolerance: 0.5 })
      expect(result.metadata[:difference]).to be_within(0.0001).of(0.4)
    end

    it "fails outside an absolute tolerance" do
      expect(eval_set.expect_within(43.0, 42.0, delta: 0.5).passed?).to eq(false)
    end

    it "reads percent as a percentage of expected" do
      expect(eval_set.expect_within(101.0, 100.0, percent: 2).passed?).to eq(true)
      expect(eval_set.expect_within(103.0, 100.0, percent: 2).passed?).to eq(false)
      expect(eval_set.expect_within(103.0, 100.0, percent: 2).description).to eq("within 2% of expected")
    end

    it "admits only an exact zero when percent is used against a zero expected" do
      expect(eval_set.expect_within(0, 0, percent: 10).passed?).to eq(true)
      expect(eval_set.expect_within(0.1, 0, percent: 10).passed?).to eq(false)
    end

    it "fails rather than raises when the value under test is not numeric" do
      result = eval_set.expect_within("about forty", 42.0, delta: 1)

      expect(result.failed?).to eq(true)
      expect(result.metadata).to eq({ actual: "about forty", expected: "42.0", tolerance: 1.0 })
    end

    it "raises when the expected value is not numeric" do
      expect { eval_set.expect_within(42.0, "42", delta: 1) }
        .to raise_error(ArgumentError, /expected value; it must be numeric/)
    end

    it "raises unless exactly one tolerance is given" do
      expect { eval_set.expect_within(42.0, 42.0) }.to raise_error(ArgumentError, /and was given neither/)
      expect { eval_set.expect_within(42.0, 42.0, delta: 1, percent: 1) }.to raise_error(ArgumentError, /and was given both/)
    end
  end

  describe "recording" do
    it "adds each matcher's result to the current eval result" do
      eval_set.expect_exact_match("a", "a")
      eval_set.expect_includes("abc", "b")
      eval_set.expect_matches("abc", /b/)
      eval_set.expect_within(1.0, 1.0, delta: 0.1)

      expect(eval_set.current_eval_result.expectation_results.map(&:description)).to eq([
        "exact match",
        "includes expected text",
        "matches expected pattern",
        "within 0.1 of expected"
      ])
      expect(eval_set.current_eval_result.expectation_results).to all(be_passed)
    end
  end
end
