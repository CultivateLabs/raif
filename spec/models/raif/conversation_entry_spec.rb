# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_conversation_entries
#
#  id                     :bigint           not null, primary key
#  completed_at           :datetime
#  creator_type           :string           not null
#  failed_at              :datetime
#  model_response_message :text
#  raw_response           :text
#  started_at             :datetime
#  user_message           :text
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  creator_id             :bigint           not null
#  raif_conversation_id   :bigint           not null
#
# Indexes
#
#  index_raif_conversation_entries_on_created_at            (created_at)
#  index_raif_conversation_entries_on_creator               (creator_type,creator_id)
#  index_raif_conversation_entries_on_raif_conversation_id  (raif_conversation_id)
#
# Foreign Keys
#
#  fk_rails_...  (raif_conversation_id => raif_conversations.id)
#
require "rails_helper"

RSpec.describe Raif::ConversationEntry, type: :model do
  let(:creator) { Raif::TestUser.create!(email: "test@example.com") }

  it "increments the conversation's entry count" do
    conversation = FB.create(:raif_conversation, creator: creator)

    expect do
      conversation.entries.create!(creator: conversation.creator)
    end.to change { conversation.reload.conversation_entries_count }.by(1)
  end

  describe "#process_entry!" do
    let(:conversation) { FB.create(:raif_test_conversation, creator: creator) }
    let(:entry) { FB.create(:raif_conversation_entry, raif_conversation: conversation, creator: creator) }

    context "when the response includes a tool call" do
      before do
        tool_calls = [{
          "name": "test_model_tool",
          "arguments": { "items": [{ "title": "foo", "description": "bar" }] }
        }]

        stub_raif_conversation(conversation) do |_messages, model_completion|
          model_completion.response_tool_calls = tool_calls

          "Hello"
        end
      end

      it "processes the entry" do
        entry.process_entry!
        expect(entry.reload).to be_completed
        expect(entry.model_response_message).to eq("Hello")
        expect(entry.raif_model_tool_invocations.count).to eq(1)
        expect(entry.raif_model_tool_invocations.first.tool_name).to eq("test_model_tool")
        expect(entry.raif_model_tool_invocations.first.tool_arguments).to eq({ "items" => [{ "title" => "foo", "description" => "bar" }] })
      end
    end

    context "when the response includes a tool call that triggers an observation back to the LLM" do
      before do
        conversation.update!(available_model_tools: ["Raif::ModelTools::CurrentTemperatureTestTool"])

        tool_calls = [{
          "provider_tool_call_id" => "abc123",
          "name": "current_temperature_test_tool",
          "arguments": { "zip_code": "12345" }
        }]

        stub_raif_conversation(conversation) do |_messages, model_completion|
          model_completion.response_tool_calls = tool_calls

          "I'll use the current_temperature_test_tool to get the current temperature in 12345"
        end
      end

      it "processes the entry, invokes the tool, and creates a follow-up entry" do
        entry.process_entry!

        # It automatically created a follow-up entry
        expect(entry.raif_conversation.entries.count).to eq(2)

        expect(entry.reload).to be_completed
        expect(entry.model_response_message).to eq("I'll use the current_temperature_test_tool to get the current temperature in 12345")
        expect(entry.raif_model_tool_invocations.count).to eq(1)

        mti = entry.raif_model_tool_invocations.first
        expect(mti.tool_name).to eq("current_temperature_test_tool")
        expect(mti.tool_arguments).to eq({ "zip_code" => "12345" })

        follow_up_entry = entry.raif_conversation.entries.newest_first.first
        expect(Raif::ConversationEntryJob).to have_been_enqueued.with(conversation_entry: follow_up_entry)

        expect(follow_up_entry.creator).to eq(entry.creator)

        llm_messages = conversation.llm_messages

        # Tool call message in new format (provider_tool_call_id excluded when nil due to .compact)
        expect(llm_messages).to eq([
          { "role" => "user", "content" => entry.user_message },
          {
            "type" => "tool_call",
            "provider_tool_call_id" => "abc123",
            "name" => "current_temperature_test_tool",
            "arguments" => { "zip_code" => "12345" },
            "assistant_message" => "I'll use the current_temperature_test_tool to get the current temperature in 12345"
          },
          {
            "type" => "tool_call_result",
            "provider_tool_call_id" => "abc123",
            "name" => "current_temperature_test_tool",
            "result" => { "temperature" => 72 }
          }
        ])
      end
    end

    context "when the response does not include a tool call" do
      before do
        stub_raif_conversation(conversation) do |_messages|
          "Hello user"
        end
      end

      it "processes the entry" do
        entry.process_entry!
        expect(entry.reload).to be_completed
        expect(entry.model_response_message).to eq("Hello user")
        expect(entry.raif_model_tool_invocations.count).to eq(0)
      end
    end

    context "when the response includes a markdown link" do
      before do
        stub_raif_conversation(conversation) do |_messages, _model_completion|
          "Here's a [link](https://example.com). It's a good link."
        end
      end

      context "when the response format is text" do
        it "leaves the link as markdown" do
          conversation.update!(response_format: "text")
          entry.process_entry!
          expect(entry.reload).to be_completed
          expect(entry.model_response_message).to eq("Here's a [link](https://example.com). It's a good link.")
        end
      end

      context "when the response format is html" do
        it "converts the link to an HTML link" do
          conversation.update!(response_format: "html")
          entry.process_entry!
          expect(entry.reload).to be_completed
          expect(entry.model_response_message).to eq("Here's a <a href=\"https://example.com\">link</a>. It's a good link.")
        end
      end
    end
  end
end
