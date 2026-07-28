# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Llms::SyntheticJsonResponseToolInputNormalizer do
  let(:schema) do
    {
      type: "object",
      additionalProperties: false,
      required: ["joke", "answer"],
      properties: {
        joke: { type: "string", minLength: 5 },
        answer: { type: "string" }
      }
    }
  end

  def normalize(input, with_schema: schema)
    described_class.call(input: input, schema: with_schema)
  end

  it "passes a schema-conforming input through" do
    input = { "joke" => "A joke", "answer" => "An answer" }

    expect(normalize(input)).to eq(input)
  end

  it "repairs nested and double-encoded payloads" do
    payload = { "joke" => "A joke", "answer" => "An answer" }

    expect(normalize({ "json_response" => payload })).to eq(payload)
    expect(normalize({ "json_response" => payload.to_json })).to eq(payload)
  end

  it "strips unknown root properties when the schema forbids them" do
    input = { "joke" => "A joke", "answer" => "An answer", "confidence" => 0.9 }

    expect(normalize(input)).to eq({ "joke" => "A joke", "answer" => "An answer" })
  end

  it "preserves unknown root properties when the schema allows them" do
    input = { "joke" => "A joke", "answer" => "An answer", "confidence" => 0.9 }

    expect(normalize(input, with_schema: schema.merge(additionalProperties: true))).to eq(input)
  end

  it "rejects candidates that violate the original schema" do
    input = { "joke" => "No", "answer" => "An answer" }

    expect(normalize(input)).to be_nil
  end

  it "accepts a valid empty object without accepting a stub repaired into one" do
    optional_schema = {
      type: "object",
      additionalProperties: false,
      properties: {
        note: { type: "string" }
      }
    }

    expect(normalize({}, with_schema: optional_schema)).to eq({})
    expect(normalize({ "query" => {} }, with_schema: optional_schema)).to be_nil
  end

  it "passes the input through when no schema is available" do
    input = { "query" => "forecast" }

    expect(normalize(input, with_schema: nil)).to eq(input)
  end
end
