# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Concerns::ToolCallValidation do
  let(:validator) do
    Class.new do
      include Raif::Concerns::ToolCallValidation
    end.new
  end

  let(:tool_map) do
    {
      Raif::TestModelTool.tool_name => Raif::TestModelTool
    }
  end

  describe "#validate_tool_call" do
    it "returns :unknown_tool when the tool name is not in the map" do
      result = validator.validate_tool_call(
        { "name" => "does_not_exist", "arguments" => { "anything" => true } },
        tool_map
      )

      expect(result.status).to eq(:unknown_tool)
      expect(result.tool_name).to eq("does_not_exist")
      expect(result.tool_klass).to be_nil
      expect(result.prepared_arguments).to be_nil
      expect(result).not_to be_ok
    end

    it "returns :non_hash_arguments when the raw arguments cannot be prepared into a Hash" do
      result = validator.validate_tool_call(
        { "name" => "test_model_tool", "arguments" => "not-a-hash" },
        tool_map
      )

      expect(result.status).to eq(:non_hash_arguments)
      expect(result.raw_arguments).to eq("not-a-hash")
      expect(result.tool_klass).to eq(Raif::TestModelTool)
      expect(result).not_to be_ok
    end

    it "returns :schema_mismatch when prepared arguments do not satisfy the schema" do
      result = validator.validate_tool_call(
        { "name" => "test_model_tool", "arguments" => { "items" => "should-be-an-array" } },
        tool_map
      )

      expect(result.status).to eq(:schema_mismatch)
      expect(result.tool_klass).to eq(Raif::TestModelTool)
      expect(result.errors).to be_a(Array)
      expect(result.errors).not_to be_empty
      expect(result).not_to be_ok
    end

    it "returns :ok with the prepared Hash when only extra unknown keys are present" do
      result = validator.validate_tool_call(
        {
          "name" => "test_model_tool",
          "arguments" => {
            "items" => [{ "title" => "foo", "description" => "bar" }],
            "length" => 2000,
            "offset" => 0
          }
        },
        tool_map
      )

      expect(result).to be_ok
      expect(result.prepared_arguments).to eq(
        "items" => [{ "title" => "foo", "description" => "bar" }]
      )
      expect(result.prepared_arguments).not_to have_key("length")
      expect(result.prepared_arguments).not_to have_key("offset")
    end

    it "returns :preparation_error when a tool's prepare_tool_arguments raises" do
      faulty_tool = Class.new(Raif::ModelTool) do
        class << self
          def tool_name
            "faulty_prepare"
          end

          def tool_description
            "test tool that raises during prepare_tool_arguments"
          end

          def tool_arguments_schema
            { type: "object", properties: {}, required: [] }
          end

          def example_model_invocation
            { "name" => tool_name, "arguments" => {} }
          end

          def process_invocation(_invocation)
            { ok: true }
          end

          def prepare_tool_arguments(_arguments)
            raise "kaboom"
          end
        end
      end

      result = validator.validate_tool_call(
        { "name" => "faulty_prepare", "arguments" => { "x" => 1 } },
        { "faulty_prepare" => faulty_tool }
      )

      expect(result.status).to eq(:preparation_error)
      expect(result.tool_klass).to eq(faulty_tool)
      expect(result.errors.first).to include("RuntimeError")
      expect(result.errors.first).to include("kaboom")
      expect(result.prepared_arguments).to be_nil
      expect(result).not_to be_ok
    end

    it "returns :ok when the arguments are fully valid" do
      result = validator.validate_tool_call(
        {
          "name" => "test_model_tool",
          "arguments" => { "items" => [{ "title" => "foo", "description" => "bar" }] }
        },
        tool_map
      )

      expect(result).to be_ok
      expect(result.tool_klass).to eq(Raif::TestModelTool)
      expect(result.prepared_arguments).to eq(
        "items" => [{ "title" => "foo", "description" => "bar" }]
      )
      expect(result.errors).to be_nil
    end
  end
end
