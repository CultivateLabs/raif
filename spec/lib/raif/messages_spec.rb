# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Messages do
  describe Raif::Messages::UserMessage do
    describe "#initialize" do
      it "creates a message with content" do
        message = described_class.new(content: "Hello, world!")
        expect(message.content).to eq("Hello, world!")
      end
    end

    describe "#to_h" do
      it "returns hash with role and content" do
        message = described_class.new(content: "Hello, world!")
        expect(message.to_h).to eq({
          "role" => "user",
          "content" => "Hello, world!"
        })
      end
    end

    describe ".from_h" do
      it "deserializes from a hash" do
        hash = { "role" => "user", "content" => "Hello, world!" }
        message = described_class.from_h(hash)
        expect(message).to be_a(described_class)
        expect(message.content).to eq("Hello, world!")
      end
    end
  end

  describe Raif::Messages::AssistantMessage do
    describe "#initialize" do
      it "creates a message with content" do
        message = described_class.new(content: "I can help with that.")
        expect(message.content).to eq("I can help with that.")
      end
    end

    describe "#to_h" do
      it "returns hash with role and content" do
        message = described_class.new(content: "I can help with that.")
        expect(message.to_h).to eq({
          "role" => "assistant",
          "content" => "I can help with that."
        })
      end
    end

    describe ".from_h" do
      it "deserializes from a hash" do
        hash = { "role" => "assistant", "content" => "I can help with that." }
        message = described_class.from_h(hash)
        expect(message).to be_a(described_class)
        expect(message.content).to eq("I can help with that.")
      end
    end
  end

  describe Raif::Messages::ToolCall do
    describe "#initialize" do
      it "creates a tool call with required params" do
        message = described_class.new(
          name: "wikipedia_search",
          arguments: { "query" => "Ruby programming" }
        )
        expect(message.name).to eq("wikipedia_search")
        expect(message.arguments).to eq({ "query" => "Ruby programming" })
        expect(message.provider_tool_call_id).to be_nil
        expect(message.assistant_message).to be_nil
      end

      it "creates a tool call with all params" do
        message = described_class.new(
          name: "wikipedia_search",
          arguments: { "query" => "Ruby programming" },
          provider_tool_call_id: "call_123",
          assistant_message: "Let me search for that."
        )
        expect(message.name).to eq("wikipedia_search")
        expect(message.arguments).to eq({ "query" => "Ruby programming" })
        expect(message.provider_tool_call_id).to eq("call_123")
        expect(message.assistant_message).to eq("Let me search for that.")
      end
    end

    describe "#to_h" do
      it "returns hash with all fields when present" do
        message = described_class.new(
          name: "wikipedia_search",
          arguments: { "query" => "Ruby" },
          provider_tool_call_id: "call_123",
          assistant_message: "Searching..."
        )
        expect(message.to_h).to eq({
          "type" => "tool_call",
          "provider_tool_call_id" => "call_123",
          "name" => "wikipedia_search",
          "arguments" => { "query" => "Ruby" },
          "assistant_message" => "Searching..."
        })
      end

      it "excludes nil optional fields (compact)" do
        message = described_class.new(
          name: "wikipedia_search",
          arguments: { "query" => "Ruby" }
        )
        result = message.to_h
        expect(result).to eq({
          "type" => "tool_call",
          "name" => "wikipedia_search",
          "arguments" => { "query" => "Ruby" }
        })
        expect(result).not_to have_key("provider_tool_call_id")
        expect(result).not_to have_key("assistant_message")
      end
    end

    describe ".from_h" do
      it "deserializes from a hash with all fields" do
        hash = {
          "type" => "tool_call",
          "provider_tool_call_id" => "call_123",
          "name" => "wikipedia_search",
          "arguments" => { "query" => "Ruby" },
          "assistant_message" => "Searching..."
        }
        message = described_class.from_h(hash)
        expect(message).to be_a(described_class)
        expect(message.name).to eq("wikipedia_search")
        expect(message.arguments).to eq({ "query" => "Ruby" })
        expect(message.provider_tool_call_id).to eq("call_123")
        expect(message.assistant_message).to eq("Searching...")
      end

      it "deserializes from a hash with minimal fields" do
        hash = {
          "type" => "tool_call",
          "name" => "wikipedia_search",
          "arguments" => { "query" => "Ruby" }
        }
        message = described_class.from_h(hash)
        expect(message).to be_a(described_class)
        expect(message.name).to eq("wikipedia_search")
        expect(message.provider_tool_call_id).to be_nil
        expect(message.assistant_message).to be_nil
      end
    end
  end

  describe Raif::Messages::ToolCallResult do
    describe "#initialize" do
      it "creates a result with required params" do
        message = described_class.new(result: { "status" => "success" })
        expect(message.result).to eq({ "status" => "success" })
        expect(message.provider_tool_call_id).to be_nil
      end

      it "creates a result with all params" do
        message = described_class.new(
          result: { "status" => "success", "data" => "Some data" },
          provider_tool_call_id: "call_123"
        )
        expect(message.result).to eq({ "status" => "success", "data" => "Some data" })
        expect(message.provider_tool_call_id).to eq("call_123")
      end
    end

    describe "#to_h" do
      it "returns hash with all fields" do
        message = described_class.new(
          result: { "status" => "success" },
          provider_tool_call_id: "call_123"
        )
        expect(message.to_h).to eq({
          "type" => "tool_call_result",
          "provider_tool_call_id" => "call_123",
          "result" => { "status" => "success" }
        })
      end

      it "compacts nil values for provider_tool_call_id" do
        message = described_class.new(result: { "status" => "success" })
        result = message.to_h
        expect(result).to eq({
          "type" => "tool_call_result",
          "result" => { "status" => "success" }
        })
        expect(result).to_not have_key("provider_tool_call_id")
      end
    end

    describe ".from_h" do
      it "deserializes from a hash" do
        hash = {
          "type" => "tool_call_result",
          "provider_tool_call_id" => "call_123",
          "result" => { "status" => "success" }
        }
        message = described_class.from_h(hash)
        expect(message).to be_a(described_class)
        expect(message.provider_tool_call_id).to eq("call_123")
        expect(message.result).to eq({ "status" => "success" })
      end
    end
  end

  describe ".from_h" do
    it "deserializes a user message" do
      hash = { "role" => "user", "content" => "Hello" }
      message = described_class.from_h(hash)
      expect(message).to be_a(Raif::Messages::UserMessage)
      expect(message.content).to eq("Hello")
    end

    it "deserializes an assistant message" do
      hash = { "role" => "assistant", "content" => "Hi there" }
      message = described_class.from_h(hash)
      expect(message).to be_a(Raif::Messages::AssistantMessage)
      expect(message.content).to eq("Hi there")
    end

    it "deserializes a tool call" do
      hash = {
        "type" => "tool_call",
        "name" => "wikipedia_search",
        "arguments" => { "query" => "Ruby" }
      }
      message = described_class.from_h(hash)
      expect(message).to be_a(Raif::Messages::ToolCall)
      expect(message.name).to eq("wikipedia_search")
    end

    it "deserializes a tool call result" do
      hash = {
        "type" => "tool_call_result",
        "provider_tool_call_id" => "call_123",
        "result" => { "status" => "success" }
      }
      message = described_class.from_h(hash)
      expect(message).to be_a(Raif::Messages::ToolCallResult)
      expect(message.result).to eq({ "status" => "success" })
    end

    it "raises ArgumentError for unknown message type" do
      hash = { "unknown" => "type" }
      expect { described_class.from_h(hash) }.to raise_error(ArgumentError, /Unknown message type/)
    end
  end

  describe ".from_array" do
    it "deserializes an array of message hashes" do
      hashes = [
        { "role" => "user", "content" => "Hello" },
        { "role" => "assistant", "content" => "Hi there" },
        { "type" => "tool_call", "name" => "search", "arguments" => {} },
        { "type" => "tool_call_result", "result" => { "data" => "result" } }
      ]

      messages = described_class.from_array(hashes)
      expect(messages.length).to eq(4)
      expect(messages[0]).to be_a(Raif::Messages::UserMessage)
      expect(messages[1]).to be_a(Raif::Messages::AssistantMessage)
      expect(messages[2]).to be_a(Raif::Messages::ToolCall)
      expect(messages[3]).to be_a(Raif::Messages::ToolCallResult)
    end

    it "returns an empty array for empty input" do
      expect(described_class.from_array([])).to eq([])
    end
  end

  describe "round-trip serialization" do
    it "preserves data through to_h -> from_h cycle" do
      original_messages = [
        Raif::Messages::UserMessage.new(content: "What is Ruby?"),
        Raif::Messages::ToolCall.new(
          name: "wikipedia_search",
          arguments: { "query" => "Ruby programming language" },
          provider_tool_call_id: "call_abc",
          assistant_message: "Let me search for that."
        ),
        Raif::Messages::ToolCallResult.new(
          provider_tool_call_id: "call_abc",
          result: { "title" => "Ruby", "content" => "A programming language..." }
        ),
        Raif::Messages::AssistantMessage.new(content: "Ruby is a programming language...")
      ]

      # Serialize to hashes
      hashes = original_messages.map(&:to_h)

      # Deserialize back to objects
      restored_messages = described_class.from_array(hashes)

      # Verify types and data match
      expect(restored_messages[0]).to be_a(Raif::Messages::UserMessage)
      expect(restored_messages[0].content).to eq("What is Ruby?")

      expect(restored_messages[1]).to be_a(Raif::Messages::ToolCall)
      expect(restored_messages[1].name).to eq("wikipedia_search")
      expect(restored_messages[1].provider_tool_call_id).to eq("call_abc")
      expect(restored_messages[1].assistant_message).to eq("Let me search for that.")

      expect(restored_messages[2]).to be_a(Raif::Messages::ToolCallResult)
      expect(restored_messages[2].provider_tool_call_id).to eq("call_abc")
      expect(restored_messages[2].result["title"]).to eq("Ruby")

      expect(restored_messages[3]).to be_a(Raif::Messages::AssistantMessage)
      expect(restored_messages[3].content).to eq("Ruby is a programming language...")
    end
  end
end
