# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Llms::Anthropic::StrictSchemaTransformer do
  describe ".call" do
    it "removes unsupported constraints recursively and folds them into descriptions" do
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
      expect(item_schema[:minItems]).to eq(1)
      expect(item_schema[:items][:properties]).to eq({
        code: {
          type: "string",
          description: "Must match the pattern /^[A-Z]+$/. Must be at least 2 characters long."
        },
        score: {
          type: "number",
          description: "Must be at least 0. Must be at most 1."
        }
      })
      expect(item_schema[:items][:required]).to eq(["code", "score"])
    end

    it "clamps minItems above 1 to 1 on the wire and preserves the real bound in the description" do
      schema = {
        type: "array",
        minItems: 4,
        items: { type: "string" }
      }

      transformed = described_class.call(schema)

      expect(transformed[:minItems]).to eq(1)
      expect(transformed[:description]).to eq("Must contain at least 4 items.")
    end

    it "keeps minItems of 0 without a description note" do
      transformed = described_class.call({ type: "array", minItems: 0, items: { type: "string" } })

      expect(transformed[:minItems]).to eq(0)
      expect(transformed).not_to have_key(:description)
    end

    it "collapses equal minItems and maxItems into an exact-count note" do
      schema = {
        type: "array",
        minItems: 4,
        maxItems: 4,
        description: "Your probability distribution across all answer options.",
        items: { type: "string" }
      }

      transformed = described_class.call(schema)

      expect(transformed[:minItems]).to eq(1)
      expect(transformed).not_to have_key(:maxItems)
      expect(transformed[:description]).to eq(
        "Your probability distribution across all answer options. Must contain exactly 4 items."
      )
    end

    it "notes a stripped maxItems on its own" do
      transformed = described_class.call({ type: "array", maxItems: 10, items: { type: "string" } })

      expect(transformed).not_to have_key(:maxItems)
      expect(transformed[:description]).to eq("Must contain at most 10 items.")
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
        pattern: { type: "string", description: "Must be at most 10 characters long." },
        legacy: { "$ref" => "#/definitions/pattern" }
      })
      expect(transformed["$defs"]["maximum"]).to eq({ type: "number", description: "Must be at most 100." })
      expect(transformed[:definitions][:pattern]).to eq({
        type: "string",
        description: "Must match the pattern /^[a-z]+$/."
      })
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
