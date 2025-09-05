# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::ConversationEntryJob, type: :job do
  include ActiveJob::TestHelper
  include ActionView::RecordIdentifier

  let(:creator) { FB.create(:raif_test_user) }
  let(:conversation) { FB.create(:raif_conversation, creator: creator) }
  let(:conversation_entry) { FB.create(:raif_conversation_entry, raif_conversation: conversation, creator: creator) }

  describe "#perform" do
    it "processes the conversation entry" do
      expect(conversation_entry).to receive(:process_entry!).and_return(conversation_entry)

      expect(Turbo::StreamsChannel).to receive(:broadcast_render_to).with(
        conversation,
        partial: "raif/conversations/entry_processed",
        locals: { conversation: conversation, conversation_entry: conversation_entry }
      )

      described_class.new.perform(conversation_entry: conversation_entry)
    end

    it "sets started_at timestamp before enqueuing" do
      expect do
        described_class.perform_later(conversation_entry: conversation_entry)
      end.to change { conversation_entry.reload.started_at }.from(nil).to(be_present)
    end

    context "when processing fails" do
      before do
        allow(conversation_entry).to receive(:process_entry!).and_raise(StandardError.new("Test error"))
      end

      it "handles the error" do
        described_class.new.perform(conversation_entry: conversation_entry)
        expect(conversation_entry.reload).to be_failed
      end
    end
  end
end
