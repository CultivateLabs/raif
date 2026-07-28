# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Concerns::Llms::Anthropic::StructuredOutputSchemaSanitization do
  let(:host){ Class.new{ include Raif::Concerns::Llms::Anthropic::StructuredOutputSchemaSanitization }.new }

  def sanitize(schema)
    host.sanitize_structured_output_schema(schema)
  end

  describe "numeric constraints" do
    it "strips every unsupported constraint from integer properties" do
      schema = {
        type: "object",
        additionalProperties: false,
        properties: {
          probability: {
            type: "integer",
            description: "0-100.",
            minimum: 0,
            maximum: 100,
            exclusiveMinimum: 0,
            exclusiveMaximum: 100,
            multipleOf: 5
          }
        },
        required: ["probability"]
      }

      expect(sanitize(schema)[:properties][:probability]).to eq({
        type: "integer",
        description: "0-100."
      })
    end

    it "strips the same constraints from number properties" do
      schema = { type: "object", properties: { score: { type: "number", minimum: 0.0, maximum: 1.0 } } }

      expect(sanitize(schema)[:properties][:score]).to eq({ type: "number" })
    end
  end

  describe "array constraints" do
    it "strips maxItems and uniqueItems" do
      schema = {
        type: "object",
        properties: {
          guids: { type: "array", maxItems: 4, uniqueItems: true, items: { type: "string" } }
        }
      }

      expect(sanitize(schema)[:properties][:guids]).to eq({
        type: "array",
        items: { type: "string" }
      })
    end

    it "keeps minItems when it is 0 or 1" do
      [0, 1].each do |value|
        schema = { type: "object", properties: { guids: { type: "array", minItems: value } } }

        expect(sanitize(schema)[:properties][:guids]).to eq({ type: "array", minItems: value })
      end
    end

    it "strips minItems when it is any other bound" do
      schema = { type: "object", properties: { guids: { type: "array", minItems: 4 } } }

      expect(sanitize(schema)[:properties][:guids]).to eq({ type: "array" })
    end
  end

  describe "object constraints" do
    it "strips minProperties and maxProperties" do
      schema = { type: "object", additionalProperties: false, minProperties: 1, maxProperties: 3, properties: {} }

      expect(sanitize(schema)).to eq({ type: "object", additionalProperties: false, properties: {} })
    end
  end

  describe "constraints Anthropic accepts" do
    it "leaves string constraints, enums, and structural keywords alone" do
      schema = {
        type: "object",
        additionalProperties: false,
        properties: {
          answer_guid: { type: "string", enum: ["a", "b"], description: "The guid." },
          slug: { type: "string", minLength: 2, maxLength: 40, pattern: "^[a-z]+$" },
          due_on: { type: "string", format: "date" }
        },
        required: ["answer_guid", "slug", "due_on"]
      }

      expect(sanitize(schema)).to eq(schema)
    end
  end

  describe "traversal" do
    it "sanitizes constraints nested inside array items" do
      schema = {
        type: "object",
        properties: {
          probabilities: {
            type: "array",
            minItems: 3,
            maxItems: 3,
            items: {
              type: "object",
              additionalProperties: false,
              properties: {
                answer_guid: { type: "string", enum: ["a", "b", "c"] },
                probability: { type: "integer", minimum: 0, maximum: 100 }
              },
              required: ["answer_guid", "probability"]
            }
          }
        },
        required: ["probabilities"]
      }

      sanitized = sanitize(schema)

      expect(sanitized[:properties][:probabilities].keys).to eq([:type, :items])
      expect(sanitized.dig(:properties, :probabilities, :items, :properties, :probability)).to eq({ type: "integer" })
      expect(sanitized.dig(:properties, :probabilities, :items, :properties, :answer_guid)).to eq({
        type: "string",
        enum: ["a", "b", "c"]
      })
    end

    it "sanitizes constraints nested inside anyOf branches and $defs" do
      schema = {
        type: "object",
        properties: {
          value: { anyOf: [{ type: "integer", minimum: 1 }, { type: "string", minLength: 1 }] }
        },
        "$defs": { count: { type: "integer", maximum: 10 } }
      }

      sanitized = sanitize(schema)

      expect(sanitized.dig(:properties, :value, :anyOf)).to eq([{ type: "integer" }, { type: "string", minLength: 1 }])
      expect(sanitized[:"$defs"][:count]).to eq({ type: "integer" })
    end

    it "handles string keys, as stored schemas use" do
      schema = {
        "type" => "object",
        "properties" => { "probability" => { "type" => "integer", "minimum" => 0, "maximum" => 100 } },
        "required" => ["probability"]
      }

      expect(sanitize(schema)["properties"]["probability"]).to eq({ "type" => "integer" })
    end

    it "does not strip properties that happen to be named after a constraint" do
      schema = {
        type: "object",
        additionalProperties: false,
        properties: {
          minimum: { type: "integer" },
          maxItems: { type: "string" },
          type: { type: "string" }
        },
        required: ["minimum", "maxItems", "type"]
      }

      expect(sanitize(schema)).to eq(schema)
    end

    it "does not mutate the schema it was given" do
      schema = { type: "object", properties: { probability: { type: "integer", minimum: 0 } } }
      original = Marshal.load(Marshal.dump(schema))

      sanitize(schema)

      expect(schema).to eq(original)
    end

    it "passes through blank schemas untouched" do
      expect(sanitize(nil)).to be_nil
      expect(sanitize({})).to eq({})
    end
  end
end
