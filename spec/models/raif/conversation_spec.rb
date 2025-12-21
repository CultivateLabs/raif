# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_conversations
#
#  id                         :bigint           not null, primary key
#  available_model_tools      :jsonb            not null
#  available_user_tools       :jsonb            not null
#  conversation_entries_count :integer          default(0), not null
#  creator_type               :string           not null
#  generating_entry_response  :boolean          default(FALSE), not null
#  llm_messages_max_length    :integer
#  llm_model_key              :string           not null
#  requested_language_key     :string
#  response_format            :integer          default("text"), not null
#  system_prompt              :text
#  type                       :string           not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  creator_id                 :bigint           not null
#
# Indexes
#
#  index_raif_conversations_on_created_at  (created_at)
#  index_raif_conversations_on_creator     (creator_type,creator_id)
#
require "rails_helper"

RSpec.describe Raif::Conversation, type: :model do
  let(:creator) { Raif::TestUser.create!(email: "test@example.com") }

  describe "#llm_messages" do
    it "returns the messages" do
      conversation = FB.create(:raif_conversation, :with_entries, creator: creator)
      expect(conversation.entries.count).to eq(3)

      messages = conversation.entries.oldest_first.map do |entry|
        [
          { "role" => "user", "content" => entry.user_message },
          { "role" => "assistant", "content" => entry.model_response_message }
        ]
      end.flatten

      expect(conversation.llm_messages).to eq(messages)
      expect(messages.length).to eq(6)
    end

    it "includes tool invocations" do
      conversation = FB.create(:raif_conversation, creator: creator)
      # Entry 1: No tool invocations, just user and assistant messages
      entry1 = FB.create(:raif_conversation_entry, :completed, raif_conversation: conversation, creator: creator)

      # Entry 2: Tool invocation with no model_response_message
      entry2 = FB.create(:raif_conversation_entry, :completed, :with_tool_invocation, raif_conversation: conversation, creator: creator)
      entry2.update_columns model_response_message: nil
      mti = entry2.raif_model_tool_invocations.first
      mti.update!(result: { "status" => "success" }, provider_tool_call_id: "call_123")

      # Entry 3: Tool invocation with model_response_message (assistant_message)
      entry3 = FB.create(:raif_conversation_entry, :completed, :with_tool_invocation, raif_conversation: conversation, creator: creator)
      mti2 = entry3.raif_model_tool_invocations.first
      mti2.update!(result: { "status" => "pending" }, provider_tool_call_id: "call_456")

      messages = [
        # Entry 1: regular user/assistant exchange
        { "role" => "user", "content" => entry1.user_message },
        { "role" => "assistant", "content" => entry1.model_response_message },
        # Entry 2: user message + tool call (no assistant_message) + tool result
        { "role" => "user", "content" => entry2.user_message },
        {
          "type" => "tool_call",
          "provider_tool_call_id" => "call_123",
          "name" => mti.tool_name,
          "arguments" => mti.tool_arguments
        },
        {
          "type" => "tool_call_result",
          "provider_tool_call_id" => "call_123",
          "name" => mti.tool_name,
          "result" => { "status" => "success" }
        },
        # Entry 3: user message + tool call (with assistant_message) + tool result
        { "role" => "user", "content" => entry3.user_message },
        {
          "type" => "tool_call",
          "provider_tool_call_id" => "call_456",
          "name" => mti2.tool_name,
          "arguments" => mti2.tool_arguments,
          "assistant_message" => entry3.model_response_message
        },
        {
          "type" => "tool_call_result",
          "provider_tool_call_id" => "call_456",
          "name" => mti2.tool_name,
          "result" => { "status" => "pending" }
        }
      ]

      expect(conversation.llm_messages).to eq(messages)
    end

    describe "llm_messages_max_length" do
      it "defaults to the config value on initialization" do
        conversation = Raif::Conversation.new(creator: creator)
        expect(conversation.llm_messages_max_length).to eq(Raif.config.conversation_llm_messages_max_length_default)
      end

      it "limits entries when llm_messages_max_length is set" do
        conversation = FB.create(:raif_conversation, :with_entries, entries_count: 5, creator: creator, llm_messages_max_length: 3)
        expect(conversation.entries.count).to eq(5)

        # Get messages from the last 3 entries (not last 3 message hashes)
        last_3_entries = conversation.entries.oldest_first.last(3)
        expected_messages = last_3_entries.map do |entry|
          [
            { "role" => "user", "content" => entry.user_message },
            { "role" => "assistant", "content" => entry.model_response_message }
          ]
        end.flatten

        expect(conversation.llm_messages.length).to eq(6) # 3 entries × 2 messages per entry
        expect(conversation.llm_messages).to eq(expected_messages)
      end

      it "returns all messages when llm_messages_max_length is nil" do
        conversation = FB.create(:raif_conversation, :with_entries, entries_count: 5, creator: creator, llm_messages_max_length: nil)
        expect(conversation.entries.count).to eq(5)

        all_messages = conversation.entries.oldest_first.map do |entry|
          [
            { "role" => "user", "content" => entry.user_message },
            { "role" => "assistant", "content" => entry.model_response_message }
          ]
        end.flatten

        expect(all_messages.length).to eq(10)
        expect(conversation.llm_messages.length).to eq(10)
        expect(conversation.llm_messages).to eq(all_messages)
      end

      it "returns all messages when llm_messages_max_length is greater than total entries" do
        conversation = FB.create(:raif_conversation, :with_entries, entries_count: 2, creator: creator, llm_messages_max_length: 100)
        expect(conversation.entries.count).to eq(2)

        all_messages = conversation.entries.oldest_first.map do |entry|
          [
            { "role" => "user", "content" => entry.user_message },
            { "role" => "assistant", "content" => entry.model_response_message }
          ]
        end.flatten

        expect(all_messages.length).to eq(4)
        expect(conversation.llm_messages.length).to eq(4)
        expect(conversation.llm_messages).to eq(all_messages)
      end
    end
  end

  it "does not allow invalid types" do
    conversation = FB.build(:raif_conversation, type: "InvalidType", creator: creator)
    expect(conversation).not_to be_valid
    expect(conversation.errors.full_messages).to include("Type is not included in the list")
    conversation.type = "Raif::TestConversation"
    expect(conversation).to be_valid
  end

  describe "#build_system_prompt" do
    let(:conversation) { FB.build(:raif_conversation, creator: creator) }
    let(:test_conversation) { FB.build(:raif_test_conversation, creator: creator) }

    it "returns the system prompt" do
      prompt = <<~PROMPT.strip
        You are a helpful assistant who is collaborating with a teammate.
      PROMPT

      expect(conversation.build_system_prompt.strip).to eq(prompt)
    end

    it "includes language preference if specified" do
      conversation.requested_language_key = "es"
      expect(conversation.build_system_prompt.strip).to end_with("You're collaborating with teammate who speaks Spanish. Please respond in Spanish.")
    end
  end

  describe "#prompt_model_for_entry_response" do
    it "returns a model completion" do
      conversation = FB.create(:raif_conversation, :with_entries, entries_count: 1, creator: creator)

      stub_raif_conversation(conversation) do |_messages|
        "Hello user"
      end

      completion = conversation.prompt_model_for_entry_response(entry: conversation.entries.first)
      expect(completion).to be_a(Raif::ModelCompletion)
      expect(completion.raw_response).to eq("Hello user")
      expect(completion.response_format).to eq("text")
    end

    it "updates the system prompt to ensure it is not stale" do
      conversation = FB.create(:raif_conversation, creator: creator)

      i = 0
      allow(Raif.config).to receive(:conversation_system_prompt_intro) do
        i += 1
        "You are a helpful assistant who is responding to message number #{i} in the conversation."
      end

      stub_raif_conversation(conversation) do |_messages|
        "Response to message number #{i}"
      end

      entry = FB.create(:raif_conversation_entry, raif_conversation: conversation, creator: creator)
      model_completion = conversation.prompt_model_for_entry_response(entry: entry)

      expect(conversation.system_prompt).to eq("You are a helpful assistant who is responding to message number 1 in the conversation.")
      expect(model_completion.system_prompt).to eq("You are a helpful assistant who is responding to message number 1 in the conversation.")

      entry = FB.create(:raif_conversation_entry, raif_conversation: conversation, creator: creator)
      model_completion = conversation.prompt_model_for_entry_response(entry: entry)

      expect(conversation.system_prompt).to eq("You are a helpful assistant who is responding to message number 2 in the conversation.")
      expect(model_completion.system_prompt).to eq("You are a helpful assistant who is responding to message number 2 in the conversation.")
    end

    it "handles errors" do
      conversation = FB.create(:raif_conversation, :with_entries, entries_count: 1, creator: creator)
      stub_raif_conversation(conversation) do |_messages|
        raise StandardError, "Test error"
      end

      entry = conversation.entries.first
      conversation.prompt_model_for_entry_response(entry: entry)

      entry.reload
      expect(entry.failed_at).to be_present
    end

    it "manages generating_entry_response flag during successful completion" do
      conversation = FB.create(:raif_conversation, :with_entries, entries_count: 1, creator: creator)

      expect(conversation.generating_entry_response).to eq(false)

      stub_raif_conversation(conversation) do |_messages|
        expect(conversation.reload.generating_entry_response).to eq(true)
        "Hello user"
      end

      conversation.prompt_model_for_entry_response(entry: conversation.entries.first)

      expect(conversation.reload.generating_entry_response).to eq(false)
    end

    it "resets generating_entry_response flag on error" do
      conversation = FB.create(:raif_conversation, :with_entries, entries_count: 1, creator: creator)

      expect(conversation.generating_entry_response).to eq(false)

      stub_raif_conversation(conversation) do |_messages|
        expect(conversation.reload.generating_entry_response).to eq(true)
        raise StandardError, "Test error"
      end

      entry = conversation.entries.first
      conversation.prompt_model_for_entry_response(entry: entry)

      expect(conversation.reload.generating_entry_response).to eq(false)
      expect(entry.reload.failed_at).to be_present
    end
  end

  describe "#process_model_response_message" do
    it "allows for conversation type-specific processing of the model response message" do
      conversation = FB.create(:raif_test_conversation, creator: creator)
      entry = FB.create(:raif_conversation_entry, raif_conversation: conversation, creator: creator)
      expect(conversation.process_model_response_message(message: "Hello jerk.", entry: entry)).to eq("Hello [REDACTED].")
    end
  end

  describe "#system_prompt_intro" do
    it "returns the config value when not a lambda" do
      conversation = FB.build(:raif_conversation, creator: creator)
      expect(conversation.system_prompt_intro).to eq("You are a helpful assistant who is collaborating with a teammate.")
    end

    it "returns a dynamic system prompt when config is a lambda" do
      conversation = FB.build(:raif_conversation, creator: creator)

      allow(Raif.config).to receive(:conversation_system_prompt_intro).and_return(->(conv) {
        "You are a helpful assistant talking to #{conv.creator.email}. Today's date is #{Date.today.strftime("%B %d, %Y")}."
      })

      expected = "You are a helpful assistant talking to #{creator.email}. Today's date is #{Date.today.strftime("%B %d, %Y")}."
      expect(conversation.system_prompt_intro).to eq(expected)
    end
  end
end
