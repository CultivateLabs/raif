# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Concerns::JsonSchemaDefinition do
  # Test class for instance-dependent schemas
  class TestInstanceDependentTask < Raif::Task
    attr_accessor :include_extra_field, :detail_level

    json_response_schema do |task|
      string "name", description: "The name"

      if task.include_extra_field
        string "extra_field", description: "An extra field"
      end

      if task.detail_level == "detailed"
        object "details", description: "Detailed information" do
          string "description", description: "A description"
        end
      end
    end

    def build_prompt
      "test"
    end
  end

  # Test class for class-level schemas (backward compatibility)
  class TestClassLevelTask < Raif::Task
    json_response_schema do
      string "title", description: "The title"
      boolean "active", description: "Whether active"
    end

    def build_prompt
      "test"
    end
  end

  # Test tool for dynamic (class-level, re-evaluated) schemas
  class TestDynamicSchemaTool < Raif::ModelTool
    cattr_accessor :include_optional_field, default: false

    tool_arguments_schema dynamic: true do
      string :query, description: "The search query"

      if TestDynamicSchemaTool.include_optional_field
        integer :max_results, description: "Maximum number of results"
      end
    end

    tool_description { "A test tool with a dynamic schema" }

    def self.example_model_invocation
      { "name" => tool_name, "arguments" => { "query" => "test" } }
    end

    def self.process_invocation(tool_invocation)
      tool_invocation.update!(result: {})
    end
  end
  describe "Raif::TestModelTool.tool_arguments_schema" do
    it "generates the correct schema" do
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
  end

  describe "Raif::ModelTools::ComplexTestTool.tool_arguments_schema" do
    it "generates the correct schema" do
      expect(Raif::ModelTools::ComplexTestTool.tool_arguments_schema).to eq({
        type: "object",
        properties: {
          title: {
            type: "string",
            description: "The title of the operation",
            minLength: 3
          },
          settings: {
            type: "object",
            description: "Configuration settings",
            properties: {
              enabled: {
                type: "boolean",
                description: "Whether the tool is enabled"
              },
              priority: {
                type: "integer",
                description: "Priority level (1-10)",
                minimum: 1,
                maximum: 10
              },
              tags: {
                type: "array",
                description: "Associated tags",
                items: {
                  type: "string"
                }
              }
            },
            required: ["enabled", "priority", "tags"],
            additionalProperties: false
          },
          products: {
            type: "array",
            description: "List of products",
            items: {
              type: "object",
              properties: {
                id: {
                  type: "integer",
                  description: "Product identifier"
                },
                name: {
                  type: "string",
                  description: "Product name"
                },
                price: {
                  type: "number",
                  description: "Product price",
                  minimum: 0
                }
              },
              required: ["id", "name", "price"],
              additionalProperties: false
            }
          }
        },
        required: ["title", "settings", "products"],
        additionalProperties: false
      })
    end
  end

  describe "Instance-dependent schemas" do
    describe "arity detection" do
      it "detects class-level schemas (arity 0)" do
        expect(TestClassLevelTask.instance_dependent_schema?(:json_response)).to be false
        expect(TestClassLevelTask.schema_defined?(:json_response)).to be true
      end

      it "detects instance-dependent schemas (arity 1)" do
        expect(TestInstanceDependentTask.instance_dependent_schema?(:json_response)).to be true
        expect(TestInstanceDependentTask.schema_defined?(:json_response)).to be true
      end
    end

    describe "class-level access" do
      it "returns schema for class-level schemas" do
        schema = TestClassLevelTask.json_response_schema
        expect(schema[:properties]).to have_key("title")
        expect(schema[:properties]).to have_key("active")
      end

      it "raises error for instance-dependent schemas" do
        expect do
          TestInstanceDependentTask.json_response_schema
        end.to raise_error(Raif::Errors::InstanceDependentSchemaError, /instance-dependent/)
      end
    end

    describe "instance-level access" do
      it "returns class-level schema for class-level schemas" do
        task = TestClassLevelTask.new
        schema = task.json_response_schema
        expect(schema[:properties]).to have_key("title")
        expect(schema[:properties]).to have_key("active")
      end

      it "builds schema with instance context for instance-dependent schemas" do
        task = TestInstanceDependentTask.new
        task.include_extra_field = false
        task.detail_level = "simple"

        schema = task.json_response_schema
        expect(schema[:properties]).to have_key("name")
        expect(schema[:properties]).not_to have_key("extra_field")
        expect(schema[:properties]).not_to have_key("details")
        expect(schema[:required]).to eq(["name"])
      end

      it "includes conditional fields when instance conditions are met" do
        task = TestInstanceDependentTask.new
        task.include_extra_field = true
        task.detail_level = "simple"

        schema = task.json_response_schema
        expect(schema[:properties]).to have_key("name")
        expect(schema[:properties]).to have_key("extra_field")
        expect(schema[:properties]).not_to have_key("details")
        expect(schema[:required]).to eq(["name", "extra_field"])
      end

      it "includes nested objects when instance conditions are met" do
        task = TestInstanceDependentTask.new
        task.include_extra_field = false
        task.detail_level = "detailed"

        schema = task.json_response_schema
        expect(schema[:properties]).to have_key("name")
        expect(schema[:properties]).not_to have_key("extra_field")
        expect(schema[:properties]).to have_key("details")
        expect(schema[:properties]["details"][:properties]).to have_key("description")
        expect(schema[:required]).to eq(["name", "details"])
      end

      it "builds different schemas for different instances" do
        task1 = TestInstanceDependentTask.new
        task1.include_extra_field = true
        task1.detail_level = "simple"

        task2 = TestInstanceDependentTask.new
        task2.include_extra_field = false
        task2.detail_level = "detailed"

        schema1 = task1.json_response_schema
        schema2 = task2.json_response_schema

        expect(schema1[:properties].keys).to eq(["name", "extra_field"])
        expect(schema2[:properties].keys).to eq(["name", "details"])
      end
    end
  end

  describe "Dynamic schemas (class-level, re-evaluated)" do
    after { TestDynamicSchemaTool.include_optional_field = false }

    it "reports schema as defined" do
      expect(TestDynamicSchemaTool.schema_defined?(:tool_arguments)).to be true
    end

    it "is not instance-dependent" do
      expect(TestDynamicSchemaTool.instance_dependent_schema?(:tool_arguments)).to be false
    end

    it "returns schema at the class level without error" do
      schema = TestDynamicSchemaTool.tool_arguments_schema
      expect(schema[:type]).to eq("object")
      expect(schema[:properties]).to have_key(:query)
    end

    it "re-evaluates the schema on each call" do
      TestDynamicSchemaTool.include_optional_field = false
      schema_without = TestDynamicSchemaTool.tool_arguments_schema
      expect(schema_without[:properties]).not_to have_key(:max_results)
      expect(schema_without[:required]).to eq(["query"])

      TestDynamicSchemaTool.include_optional_field = true
      schema_with = TestDynamicSchemaTool.tool_arguments_schema
      expect(schema_with[:properties]).to have_key(:max_results)
      expect(schema_with[:required]).to eq(["query", "max_results"])
    end

    it "works via the instance method" do
      tool = TestDynamicSchemaTool.new
      schema = tool.tool_arguments_schema
      expect(schema[:properties]).to have_key(:query)
    end
  end
end
