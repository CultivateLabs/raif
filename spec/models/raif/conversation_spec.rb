# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Conversation, type: :model do
  let(:creator) { Raif::TestUser.create!(email: "test@example.com") }

  describe "#llm_messages" do
    it "returns the messages" do
      conversation = FB.create(:raif_conversation, :with_entries, creator: creator)
      expect(conversation.entries.count).to eq(3)

      messages = conversation.entries.oldest_first.map do |entry|
        [
          { "role" => "user", "content" => entry.full_user_message },
          { "role" => "assistant", "content" => entry.model_response_message }
        ]
      end.flatten

      expect(conversation.llm_messages).to eq(messages)
      expect(messages.length).to eq(6)
    end
  end

  it "does not allow invalid types" do
    conversation = FB.build(:raif_conversation, type: "InvalidType", creator: creator)
    expect(conversation).not_to be_valid
    expect(conversation.errors.full_messages).to include("Type is not included in the list")
    conversation.type = "Raif::TestConversation"
    expect(conversation).to be_valid
  end
end
