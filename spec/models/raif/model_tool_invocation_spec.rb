# frozen_string_literal: true

require "rails_helper"
require "support/test_model_tool"

RSpec.describe Raif::ModelToolInvocation, type: :model do
  it "requires the tool_arguments schema to be valid based on the tool invoked" do
    completion = FB.build(:raif_completion)
    tool_invocation = described_class.new(tool_arguments: nil, source: completion, tool_type: "Raif::TestModelTool")
    expect(tool_invocation.valid?).to eq(false)
    expect(tool_invocation.errors[:tool_arguments]).to include("does not match schema")

    tool_invocation = described_class.new(tool_arguments: { "foo" => "bar" }, source: completion, tool_type: "Raif::TestModelTool")
    expect(tool_invocation.valid?).to eq(false)
    expect(tool_invocation.errors[:tool_arguments]).to include("does not match schema")

    tool_invocation = described_class.new(tool_arguments: [{ "foo" => "bar" }], source: completion, tool_type: "Raif::TestModelTool")
    expect(tool_invocation.valid?).to eq(false)
    expect(tool_invocation.errors[:tool_arguments]).to include("does not match schema")

    # With valid schema
    tool_invocation = described_class.new(
      tool_arguments: [{ "title" => "foo", "description" => "bar" }],
      source: completion,
      tool_type: "Raif::TestModelTool"
    )
    expect(tool_invocation.valid?).to eq(true)
    expect(tool_invocation.errors[:tool_arguments]).to_not include("does not match schema")
  end
end
