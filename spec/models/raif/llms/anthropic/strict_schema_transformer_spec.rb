# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Llms::Anthropic::StrictSchemaTransformer do
  describe ".call" do
    it "removes unsupported constraints recursively while preserving supported schema structure" do
      schema = {
        type: "object",
        additionalProperties: false,
        required: ["items"],
        properties: {
          items: {
            type: "array",
            minItems: 1,
            items: {
              type: "object",
              additionalProperties: false,
              required: ["code", "score"],
              properties: {
                code: { type: "string", pattern: "^[A-Z]+$", minLength: 2 },
                score: { type: "number", minimum: 0, maximum: 1 }
              }
            }
          }
        }
      }

      transformed = described_class.call(schema)

      item_schema = transformed[:properties][:items]
      expect(item_schema).not_to have_key(:minItems)
      expect(item_schema[:items][:properties]).to eq({
        code: { type: "string" },
        score: { type: "number" }
      })
      expect(item_schema[:items][:required]).to eq(["code", "score"])
    end

    it "preserves user-defined names under schema name maps" do
      schema = {
        type: "object",
        additionalProperties: false,
        required: ["minimum", "pattern", "legacy"],
        properties: {
          minimum: { "$ref" => "#/$defs/maximum" },
          pattern: { type: "string", maxLength: 10 },
          legacy: { "$ref" => "#/definitions/pattern" }
        },
        "$defs" => {
          "maximum" => { type: "number", maximum: 100 }
        },
        definitions: {
          pattern: { type: "string", pattern: "^[a-z]+$" }
        }
      }

      transformed = described_class.call(schema)

      expect(transformed[:properties]).to eq({
        minimum: { "$ref" => "#/$defs/maximum" },
        pattern: { type: "string" },
        legacy: { "$ref" => "#/definitions/pattern" }
      })
      expect(transformed["$defs"]["maximum"]).to eq({ type: "number" })
      expect(transformed[:definitions][:pattern]).to eq({ type: "string" })
    end

    it "does not mutate the original schema" do
      schema = {
        type: "object",
        properties: { score: { type: "number", minimum: 0 } }
      }

      expect { described_class.call(schema) }.not_to change { schema }
    end
  end
end
