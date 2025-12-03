# frozen_string_literal: true

module Raif
  # Message types for agent conversation_history and conversation llm_messages.
  #
  # These classes provide a structured API for creating messages that get stored
  # as JSONB and passed to LLM providers. Each class has:
  # - Named parameters for initialization
  # - `to_h` for converting to hash format (for storage/API calls)
  # - `from_h` class method for deserializing from stored hashes
  #
  # @example Creating messages
  #   message = Raif::Messages::ToolCall.new(
  #     name: "wikipedia_search",
  #     arguments: { query: "Ruby" },
  #     provider_tool_call_id: "call_123"
  #   )
  #   conversation_history << message.to_h
  #
  # @example Deserializing stored messages
  #   messages = Raif::Messages.from_array(agent.conversation_history)
  #   messages.each do |msg|
  #     case msg
  #     when Raif::Messages::ToolCall
  #       puts "Tool: #{msg.name}"
  #     when Raif::Messages::UserMessage
  #       puts "User: #{msg.content}"
  #     end
  #   end
  module Messages
    # User role message
    class UserMessage
      attr_reader :content

      # @param content [String] The user's message content
      def initialize(content:)
        @content = content
      end

      # @return [Hash] Hash representation for JSONB storage and LLM APIs
      def to_h
        { "role" => "user", "content" => content }
      end

      # Deserialize from a hash
      # @param hash [Hash] A hash with "content" key
      # @return [UserMessage]
      def self.from_h(hash)
        new(content: hash["content"])
      end
    end

    # Assistant role message
    class AssistantMessage
      attr_reader :content

      # @param content [String] The assistant's message content
      def initialize(content:)
        @content = content
      end

      # @return [Hash] Hash representation for JSONB storage and LLM APIs
      def to_h
        { "role" => "assistant", "content" => content }
      end

      # Deserialize from a hash
      # @param hash [Hash] A hash with "content" key
      # @return [AssistantMessage]
      def self.from_h(hash)
        new(content: hash["content"])
      end
    end

    # Tool invocation request from the assistant
    class ToolCall
      attr_reader :provider_tool_call_id, :name, :arguments, :assistant_message

      # @param name [String] The tool name (snake_case)
      # @param arguments [Hash] The arguments passed to the tool
      # @param provider_tool_call_id [String, nil] Provider-assigned ID for the tool call
      # @param assistant_message [String, nil] Optional assistant message accompanying the tool call
      def initialize(name:, arguments:, provider_tool_call_id: nil, assistant_message: nil)
        @provider_tool_call_id = provider_tool_call_id
        @name = name
        @arguments = arguments
        @assistant_message = assistant_message
      end

      # @return [Hash] Hash representation for JSONB storage and LLM APIs
      def to_h
        {
          "type" => "tool_call",
          "provider_tool_call_id" => provider_tool_call_id,
          "name" => name,
          "arguments" => arguments,
          "assistant_message" => assistant_message
        }.compact
      end

      # Deserialize from a hash
      # @param hash [Hash] A hash with tool call fields
      # @return [ToolCall]
      def self.from_h(hash)
        new(
          name: hash["name"],
          arguments: hash["arguments"],
          provider_tool_call_id: hash["provider_tool_call_id"],
          assistant_message: hash["assistant_message"]
        )
      end
    end

    # Result of a tool invocation
    class ToolCallResult
      attr_reader :provider_tool_call_id, :result

      # @param result [Hash, String] The result returned by the tool
      # @param provider_tool_call_id [String, nil] Provider-assigned ID matching the tool call
      def initialize(result:, provider_tool_call_id: nil)
        @provider_tool_call_id = provider_tool_call_id
        @result = result
      end

      # @return [Hash] Hash representation for JSONB storage and LLM APIs
      def to_h
        {
          "type" => "tool_call_result",
          "provider_tool_call_id" => provider_tool_call_id,
          "result" => result
        }.compact
      end

      # Deserialize from a hash
      # @param hash [Hash] A hash with tool call result fields
      # @return [ToolCallResult]
      def self.from_h(hash)
        new(
          provider_tool_call_id: hash["provider_tool_call_id"],
          result: hash["result"]
        )
      end
    end

    class << self
      # Deserialize a single message hash into the appropriate message class
      # @param hash [Hash] A message hash with either "role" or "type" key
      # @return [UserMessage, AssistantMessage, ToolCall, ToolCallResult]
      # @raise [ArgumentError] if the hash doesn't match a known message type
      def from_h(hash)
        if hash["type"] == "tool_call"
          ToolCall.from_h(hash)
        elsif hash["type"] == "tool_call_result"
          ToolCallResult.from_h(hash)
        elsif hash["role"] == "user"
          UserMessage.from_h(hash)
        elsif hash["role"] == "assistant"
          AssistantMessage.from_h(hash)
        else
          raise ArgumentError, "Unknown message type: #{hash.inspect}"
        end
      end

      # Deserialize an array of message hashes
      # @param messages [Array<Hash>] Array of message hashes
      # @return [Array<UserMessage, AssistantMessage, ToolCall, ToolCallResult>]
      def from_array(messages)
        messages.map { |msg| from_h(msg) }
      end
    end
  end
end
