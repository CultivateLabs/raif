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
      entry1 = FB.create(:raif_conversation_entry, :completed, raif_conversation: conversation, creator: creator)
      entry2 = FB.create(:raif_conversation_entry, :completed, :with_tool_invocation, raif_conversation: conversation, creator: creator)
      entry2.update_columns model_response_message: nil
      entry2.raif_model_tool_invocations.first.update!(result: { "status": "success" })
      entry3 = FB.create(:raif_conversation_entry, :completed, :with_tool_invocation, raif_conversation: conversation, creator: creator)

      mti = entry2.raif_model_tool_invocations.first
      mti2 = entry3.raif_model_tool_invocations.first
      allow(mti2).to receive(:result_llm_message).and_return(nil)

      messages = [
        { "role" => "user", "content" => entry1.user_message },
        { "role" => "assistant", "content" => entry1.model_response_message },
        { "role" => "user", "content" => entry2.user_message },
        { "role" => "assistant", "content" => "Invoking tool: #{mti.tool_name} with arguments: #{mti.tool_arguments.to_json}" },
        { "role" => "assistant", "content" => "Mock Observation for #{mti.id}. Result was: success" },
        { "role" => "user", "content" => entry3.user_message },
        { "role" => "assistant", "content" => entry3.model_response_message },
        { "role" => "assistant", "content" => "Invoking tool: #{mti2.tool_name} with arguments: #{mti2.tool_arguments.to_json}" }
      ]

      expect(conversation.llm_messages).to eq(messages)
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
