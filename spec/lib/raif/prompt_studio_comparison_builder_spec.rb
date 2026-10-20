# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::PromptStudioComparisonBuilder do
  let(:task) { FB.build(:raif_test_task, prompt: "Line one\r\nLine two") }

  it "does not report a change when the prompts differ only in line endings" do
    allow(task).to receive(:build_prompt).and_return("Line one\nLine two")

    comparison = described_class.build(task)

    expect(comparison[:prompt_changed]).to be(false)
    expect(comparison[:prompt_diff]).to be_nil
  end

  it "builds a diff when the prompt text changed" do
    allow(task).to receive(:build_prompt).and_return("Line one\nLine three")

    comparison = described_class.build(task)

    expect(comparison[:prompt_changed]).to be(true)
    expect(comparison[:prompt_diff].map(&:action)).to eq([:unchanged, :deleted, :added])
  end
end
