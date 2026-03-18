# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::ModelTool, type: :model do
  describe ".prepare_tool_arguments" do
    it "strips unknown keys from arguments" do
      result = Raif::TestModelTool.prepare_tool_arguments(
        "items" => [{ "title" => "foo", "description" => "bar" }],
        "length" => 2000,
        "offset" => 0
      )

      expect(result).to eq("items" => [{ "title" => "foo", "description" => "bar" }])
    end

    it "logs a warning when keys are stripped" do
      expect(Rails.logger).to receive(:warn).with(/Stripped unexpected tool arguments.*length, offset/)

      Raif::TestModelTool.prepare_tool_arguments(
        "items" => [{ "title" => "foo", "description" => "bar" }],
        "length" => 2000,
        "offset" => 0
      )
    end

    it "passes through valid arguments unchanged" do
      args = { "items" => [{ "title" => "foo", "description" => "bar" }] }

      expect(Rails.logger).not_to receive(:warn)
      result = Raif::TestModelTool.prepare_tool_arguments(args)

      expect(result).to eq(args)
    end

    it "returns non-Hash arguments as-is" do
      expect(Raif::TestModelTool.prepare_tool_arguments("not a hash")).to eq("not a hash")
      expect(Raif::TestModelTool.prepare_tool_arguments(nil)).to be_nil
    end

    it "normalizes symbol keys to string keys" do
      result = Raif::TestModelTool.prepare_tool_arguments(
        items: [{ "title" => "foo", "description" => "bar" }],
        length: 2000
      )

      expect(result).to eq("items" => [{ "title" => "foo", "description" => "bar" }])
    end
  end

  describe "tool_arguments_schema" do
    it "returns the tool_arguments_schema" do
      expect(Raif::TestModelTool.tool_arguments_schema).to eq({
        type: "object",
        additionalProperties: false,
        required: ["items"],
        properties: {
          items: {
            type: "array",
            items: {
              type: "object",
              additionalProperties: false,
              properties: {
                title: { type: "string", description: "The title of the item" },
                description: { type: "string" },
              },
              required: ["title", "description"],
            }
          }
        }
      })
    end

    it "validates against OpenAI's rules" do
      llm = Raif.llm(:open_ai_gpt_4o_mini)
      expect(llm.validate_json_schema!(Raif::TestModelTool.tool_arguments_schema)).to eq(true)
    end
  end
end
