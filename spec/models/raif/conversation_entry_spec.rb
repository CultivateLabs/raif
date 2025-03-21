# frozen_string_literal: true

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
        stub_raif_conversation(conversation) do |_messages|
          <<~JSON.strip
            {
              "message" : "Hello",
              "tool" : {
                "name": "test_model_tool",
                "arguments": [{ "title": "foo", "description": "bar" }]
              }
            }
          JSON
        end
      end

      it "processes the entry" do
        entry.process_entry!
        expect(entry.reload).to be_completed
        expect(entry.model_response_message).to eq("Hello")
        expect(entry.raif_model_tool_invocations.count).to eq(1)
        expect(entry.raif_model_tool_invocations.first.tool_name).to eq("test_model_tool")
        expect(entry.raif_model_tool_invocations.first.tool_arguments).to eq([{ "title" => "foo", "description" => "bar" }])
      end
    end

    context "when the response does not include a tool call" do
      before do
        stub_raif_conversation(conversation) do |_messages|
          <<~JSON.strip
            {
              "message" : "Hello"
            }
          JSON
        end
      end

      it "processes the entry" do
        entry.process_entry!
        expect(entry.reload).to be_completed
        expect(entry.model_response_message).to eq("Hello")
        expect(entry.raif_model_tool_invocations.count).to eq(0)
      end
    end

    context "when the response contains malformed JSON" do
      before do
        stub_raif_conversation(conversation) do |_messages|
          "This is not valid JSON"
        end
      end

      it "marks the entry as failed" do
        entry.process_entry!
        expect(entry.reload).to be_failed
        expect(entry.model_response_message).to be_nil
        expect(entry.raif_model_tool_invocations.count).to eq(0)
      end
    end

    context "when the response is empty" do
      before do
        stub_raif_conversation(conversation) do |_messages|
          nil
        end
      end

      it "marks the entry as failed" do
        entry.process_entry!
        expect(entry.reload).to be_failed
        expect(entry.model_response_message).to be_nil
        expect(entry.raif_model_tool_invocations.count).to eq(0)
      end
    end
  end
end
