# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_model_tool_invocations
#
#  id                    :bigint           not null, primary key
#  completed_at          :datetime
#  failed_at             :datetime
#  result                :jsonb            not null
#  source_type           :string           not null
#  tool_arguments        :jsonb            not null
#  tool_type             :string           not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  provider_tool_call_id :string
#  source_id             :bigint           not null
#
# Indexes
#
#  index_raif_model_tool_invocations_on_source  (source_type,source_id)
#
require "rails_helper"

RSpec.describe Raif::ModelToolInvocation, type: :model do
  describe "validations" do
    it "validates presence of tool_type" do
      invocation = described_class.new
      expect(invocation).not_to be_valid
      expect(invocation.errors[:tool_type]).to include("can't be blank")
    end

    it "validates tool_arguments against schema" do
      # Valid arguments
      invocation = described_class.new(
        source: FB.build(:raif_test_task),
        tool_type: "Raif::TestModelTool",
        tool_arguments: { "items": [{ "title": "foo", "description": "bar" }] }
      )
      expect(invocation).to be_valid

      # Invalid arguments
      invocation.tool_arguments = { "foo": "bar" }
      expect(invocation).not_to be_valid
      expect(invocation.errors[:tool_arguments]).to include("does not match schema")

      # Missing "description" key"
      invocation.tool_arguments = { "items": [{ "title": "foo" }] }
      expect(invocation).not_to be_valid
      expect(invocation.errors[:tool_arguments]).to include("does not match schema")

      # Missing top level "items" object/key
      invocation.tool_arguments = [{ "title": "foo", "description": "bar" }]
      expect(invocation).not_to be_valid
      expect(invocation.errors[:tool_arguments]).to include("does not match schema")
    end
  end
end
