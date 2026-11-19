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

    context "when the entry runs tool calls" do
      let(:conversation) { Raif::DurableRunTestConversation.create!(creator: creator) }
      let(:conversation_entry) { conversation.entries.create!(creator: creator, user_message: "Look these up") }
      let(:broadcasts) { [] }

      def tool_call(name, id)
        { "provider_tool_call_id" => id, "name" => name, "arguments" => { "query" => "q" } }
      end

      def script_tool_calls(*tool_calls)
        requested = false
        stub_raif_conversation(Raif::DurableRunTestConversation) do |_messages, model_completion|
          model_completion.response_tool_calls = requested ? [] : tool_calls
          requested = true
          "On it."
        end
      end

      before do
        recorded = broadcasts
        # What a host form would render from: the state of the records at broadcast time.
        allow(Turbo::StreamsChannel).to receive(:broadcast_render_to) do |_stream, locals:, **|
          recorded << {
            generating: locals[:conversation].generating_entry_response,
            completed: locals[:conversation_entry].completed?,
            failed: locals[:conversation_entry].failed?
          }
        end
        allow(Rails.error).to receive(:report)
      end

      it "ends a single tool call with one update that shows the conversation as no longer generating" do
        script_tool_calls(tool_call("durable_run_test_tool", "call_1"))
        described_class.perform_later(conversation_entry: conversation_entry)
        perform_enqueued_jobs(only: described_class)

        expect(conversation_entry.reload).to be_completed
        expect(conversation.reload.generating_entry_response).to be(false)
        expect(broadcasts).to eq([{ generating: false, completed: true, failed: false }])
      end

      it "leaves the final update of several tool calls to the last tool job" do
        script_tool_calls(tool_call("durable_run_test_tool", "call_1"), tool_call("durable_run_second_test_tool", "call_2"))
        described_class.perform_later(conversation_entry: conversation_entry)
        perform_enqueued_jobs(only: described_class)

        expect(conversation_entry.reload).to be_waiting_on_tools
        expect(broadcasts).to be_empty

        perform_enqueued_jobs(only: Raif::ModelToolInvocationJob)

        expect(conversation_entry.reload).to be_completed
        expect(broadcasts).to eq([{ generating: false, completed: true, failed: false }])
      end

      it "shows the conversation as no longer generating when the tool call fails the entry" do
        Raif::DurableRunTestTool.behavior { raise "tool exploded" }
        script_tool_calls(tool_call("durable_run_test_tool", "call_1"))
        described_class.perform_later(conversation_entry: conversation_entry)
        perform_enqueued_jobs(only: described_class)

        expect(conversation_entry.reload).to be_failed
        expect(broadcasts).not_to be_empty
        expect(broadcasts).to all(eq(generating: false, completed: false, failed: true))
      end
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
