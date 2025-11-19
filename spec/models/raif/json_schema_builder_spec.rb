# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::JsonSchemaBuilder do
  subject(:builder) { described_class.new }

  describe "#string" do
    it "adds a string property" do
      builder.string "name", description: "User name"
      schema = builder.to_schema

      expect(schema[:properties]["name"]).to include(
        type: "string",
        description: "User name"
      )
      expect(schema[:required]).to include("name")
    end
  end

  describe "#integer" do
    it "adds an integer property" do
      builder.integer "age", description: "User age", minimum: 18
      schema = builder.to_schema

      expect(schema[:properties]["age"]).to include(
        type: "integer",
        description: "User age",
        minimum: 18
      )
      expect(schema[:required]).to include("age")
    end
  end

  describe "#boolean" do
    it "adds a boolean property" do
      builder.boolean "active", description: "Is active"
      schema = builder.to_schema

      expect(schema[:properties]["active"]).to include(
        type: "boolean",
        description: "Is active"
      )
      expect(schema[:required]).to include("active")
    end
  end

  describe "#number" do
    it "adds a number property" do
      builder.number "price", description: "Product price", minimum: 0
      schema = builder.to_schema

      expect(schema[:properties]["price"]).to include(
        type: "number",
        description: "Product price",
        minimum: 0
      )
      expect(schema[:required]).to include("price")
    end
  end

  describe "#object" do
    it "adds a nested object property" do
      builder.object "profile", description: "User profile" do
        string "bio", description: "User biography"
      end
      schema = builder.to_schema

      # Check that the profile object is correctly defined
      expect(schema[:properties]["profile"]).to include(
        type: "object",
        description: "User profile"
      )

      # Check that the bio property is correctly defined in the nested object
      profile_props = schema[:properties]["profile"][:properties]
      expect(profile_props).to be_a(Hash)
      expect(profile_props["bio"]).to include(
        type: "string",
        description: "User biography"
      )

      # Verify that the profile object itself is required in the parent schema
      expect(schema[:required]).to include("profile")
    end
  end

  describe "#array" do
    it "adds an array property with object items" do
      builder.array "friends", description: "User friends" do
        object do
          string "name", description: "Friend name"
        end
      end
      schema = builder.to_schema

      expect(schema[:properties]["friends"]).to include(
        type: "array",
        description: "User friends"
      )
      expect(schema[:properties]["friends"][:items]).to include(
        type: "object"
      )
      expect(schema[:properties]["friends"][:items][:properties]["name"]).to include(
        type: "string",
        description: "Friend name"
      )
      expect(schema[:required]).to include("friends")
    end

    it "adds an array property with primitive items" do
      builder.array "tags", description: "User tags" do
        items type: "string"
      end
      schema = builder.to_schema

      expect(schema[:properties]["tags"]).to include(
        type: "array",
        description: "User tags",
        items: { type: "string" }
      )
      expect(schema[:required]).to include("tags")
    end
  end

  describe "#to_schema" do
    it "generates a valid JSON schema" do
      builder.string "name", description: "User name"
      builder.integer "age", description: "User age", minimum: 18
      builder.string "email", description: "User email", format: "email"

      schema = builder.to_schema

      expect(schema).to eq({
        type: "object",
        additionalProperties: false,
        properties: {
          "name" => { type: "string", description: "User name" },
          "age" => { type: "integer", description: "User age", minimum: 18 },
          "email" => { type: "string", description: "User email", format: "email" }
        },
        required: ["name", "age", "email"]
      })
    end
  end

  describe "#build_with_instance" do
    let(:test_object) do
      obj = Object.new
      obj.instance_eval do
        def include_email?
          true
        end

        def detail_level
          "detailed"
        end

        def tags
          ["ruby", "rails"]
        end
      end
      obj
    end

    it "builds schema with access to instance methods" do
      builder.build_with_instance(test_object) do |instance|
        string "name", description: "User name"

        if instance.include_email?
          string "email", description: "User email"
        end
      end

      schema = builder.to_schema

      expect(schema[:properties]).to have_key("name")
      expect(schema[:properties]).to have_key("email")
      expect(schema[:required]).to eq(["name", "email"])
    end

    it "conditionally includes fields based on instance state" do
      simple_object = Object.new
      simple_object.instance_eval do
        def include_email?
          false
        end
      end

      builder.build_with_instance(simple_object) do |instance|
        string "name", description: "User name"

        if instance.include_email?
          string "email", description: "User email"
        end
      end

      schema = builder.to_schema

      expect(schema[:properties]).to have_key("name")
      expect(schema[:properties]).not_to have_key("email")
      expect(schema[:required]).to eq(["name"])
    end

    it "supports complex conditional logic" do
      builder.build_with_instance(test_object) do |instance|
        string "name", description: "User name"

        if instance.detail_level == "detailed"
          object "profile", description: "User profile" do
            string "bio", description: "Biography"
            array "interests", description: "Interests" do
              items type: "string"
            end
          end
        end
      end

      schema = builder.to_schema

      expect(schema[:properties]).to have_key("name")
      expect(schema[:properties]).to have_key("profile")
      expect(schema[:properties]["profile"][:properties]).to have_key("bio")
      expect(schema[:properties]["profile"][:properties]).to have_key("interests")
    end

    it "can use instance data in field definitions" do
      builder.build_with_instance(test_object) do |instance|
        string "name", description: "User name"
        array "tags", description: "User tags (default: #{instance.tags.join(", ")})" do
          items type: "string"
        end
      end

      schema = builder.to_schema

      expect(schema[:properties]["tags"][:description]).to eq("User tags (default: ruby, rails)")
    end
  end
end
