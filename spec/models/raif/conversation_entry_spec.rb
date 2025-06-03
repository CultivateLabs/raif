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
