# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::PromptDiff do
  def summarize(lines)
    lines.map { |line| [line.action, line.segments.map { |segment| [segment.text, segment.changed] }] }
  end

  it "returns only unchanged lines for equal text" do
    lines = described_class.build("Line one\nLine two\n", "Line one\nLine two")

    expect(summarize(lines)).to eq([
      [:unchanged, [["Line one", false]]],
      [:unchanged, [["Line two", false]]]
    ])
  end

  it "marks an added line" do
    lines = described_class.build("One\nThree", "One\nTwo\nThree")

    expect(summarize(lines)).to eq([
      [:unchanged, [["One", false]]],
      [:added, [["Two", true]]],
      [:unchanged, [["Three", false]]]
    ])
  end

  it "marks a deleted line" do
    lines = described_class.build("One\nTwo\nThree", "One\nThree")

    expect(summarize(lines)).to eq([
      [:unchanged, [["One", false]]],
      [:deleted, [["Two", true]]],
      [:unchanged, [["Three", false]]]
    ])
  end

  it "highlights the changed words inside a changed line pair" do
    lines = described_class.build("Answer in English.", "Answer in French.")

    expect(summarize(lines)).to eq([
      [:deleted, [["Answer in ", false], ["English", true], [".", false]]],
      [:added, [["Answer in ", false], ["French", true], [".", false]]]
    ])
  end

  it "highlights the whole line pair when the lines share less than half of their words" do
    lines = described_class.build("You are a helpful assistant.", "Return only valid JSON output.")

    expect(summarize(lines)).to eq([
      [:deleted, [["You are a helpful assistant.", true]]],
      [:added, [["Return only valid JSON output.", true]]]
    ])
  end

  it "lists all deleted lines of a changed block before its added lines" do
    lines = described_class.build("a1\na2\nkeep", "b1\nb2\nkeep")

    expect(lines.map(&:action)).to eq([:deleted, :deleted, :added, :added, :unchanged])
  end

  it "skips the word diff when a line exceeds the token limit" do
    stub_const("Raif::PromptDiff::WORD_DIFF_TOKEN_LIMIT", 3)

    lines = described_class.build("one two three", "one two four")

    expect(summarize(lines)).to eq([
      [:deleted, [["one two three", true]]],
      [:added, [["one two four", true]]]
    ])
  end
end
