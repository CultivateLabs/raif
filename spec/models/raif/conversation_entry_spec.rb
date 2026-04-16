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

  describe "#add_user_tool_invocation_to_user_message" do
    let(:conversation) { FB.create(:raif_test_conversation, creator: creator) }

    it "appends the tool invocation message with newlines" do
      entry = conversation.entries.build(
        creator: creator,
        user_message: "Hello"
      )

      tool_invocation = instance_double(Raif::UserToolInvocation, as_user_message: "Tool result here")
      allow(tool_invocation).to receive(:present?).and_return(true)
      allow(entry).to receive(:raif_user_tool_invocation).and_return(tool_invocation)

      entry.add_user_tool_invocation_to_user_message
      expect(entry.user_message).to eq("Hello\n\nTool result here")
    end

    it "does not modify user_message when no tool invocation is present" do
      entry = conversation.entries.create!(creator: creator, user_message: "Hello")
      expect(entry.user_message).to eq("Hello")
    end
  end

  describe "associations" do
    let(:conversation) { FB.create(:raif_test_conversation, creator: creator) }
    let(:entry) { FB.create(:raif_conversation_entry, raif_conversation: conversation, creator: creator) }

    def create_model_completion(source:)
      FB.create(:raif_model_completion, source: source, model_api_name: "test-model")
    end

    it "has_many :raif_model_completions in created_at ascending order" do
      old_mc = create_model_completion(source: entry)
      new_mc = create_model_completion(source: entry)
      old_mc.update_columns(created_at: 2.minutes.ago)

      expect(entry.raif_model_completions.to_a).to eq([old_mc, new_mc])
    end

    it "singular raif_model_completion returns the newest completion" do
      old_mc = create_model_completion(source: entry)
      new_mc = create_model_completion(source: entry)
      old_mc.update_columns(created_at: 2.minutes.ago)

      expect(entry.reload.raif_model_completion).to eq(new_mc)
    end

    it "returns the newest completion even when eager-loaded with includes(:raif_model_completion)" do
      old_mc = create_model_completion(source: entry)
      new_mc = create_model_completion(source: entry)
      old_mc.update_columns(created_at: 2.minutes.ago)

      loaded = Raif::ConversationEntry.includes(:raif_model_completion).find(entry.id)
      expect(loaded.raif_model_completion).to eq(new_mc)
    end

    it "destroys all associated model completions when the entry is destroyed" do
      create_model_completion(source: entry)
      create_model_completion(source: entry)

      expect { entry.destroy! }.to change {
        Raif::ModelCompletion.where(source_type: "Raif::ConversationEntry", source_id: entry.id).count
      }.from(2).to(0)
    end
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
            "result" => "The current temperature for zip code 12345 is 72 degrees Fahrenheit."
          }
        ])
      end
    end

    context "when the response includes a tool call with extra arguments" do
      before do
        tool_calls = [{
          "name": "test_model_tool",
          "arguments": { "items": [{ "title": "foo", "description": "bar" }], "length": 2000, "offset": 0 }
        }]

        stub_raif_conversation(conversation) do |_messages, model_completion|
          model_completion.response_tool_calls = tool_calls

          "Hello"
        end
      end

      it "strips the extra arguments and completes successfully" do
        entry.process_entry!
        expect(entry.reload).to be_completed
        expect(entry.raif_model_tool_invocations.count).to eq(1)

        invocation = entry.raif_model_tool_invocations.first
        expect(invocation.tool_arguments).to eq({ "items" => [{ "title" => "foo", "description" => "bar" }] })
        expect(invocation.tool_arguments).not_to have_key("length")
        expect(invocation.tool_arguments).not_to have_key("offset")
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

    context "when the response includes a tool call with malformed (String) arguments" do
      let(:invalid_tool_call) do
        [{
          "provider_tool_call_id" => "tooluse_bad",
          "name" => "test_model_tool",
          "arguments" => "{\n \" \"06    \" States president 202"
        }]
      end

      let(:valid_tool_call) do
        [{
          "provider_tool_call_id" => "tooluse_good",
          "name" => "test_model_tool",
          "arguments" => { "items" => [{ "title" => "foo", "description" => "bar" }] }
        }]
      end

      it "re-prompts with synthetic feedback and succeeds on the retry" do
        attempts = 0
        stub_raif_conversation(conversation) do |_messages, model_completion|
          attempts += 1
          if attempts == 1
            model_completion.response_tool_calls = invalid_tool_call
            ""
          else
            model_completion.response_tool_calls = valid_tool_call
            "Here you go"
          end
        end

        entry.process_entry!

        expect(entry.reload).to be_completed
        expect(entry.model_response_message).to eq("Here you go")
        expect(entry.raif_model_tool_invocations.count).to eq(1)
        expect(entry.raif_model_tool_invocations.first.tool_arguments).to eq(
          "items" => [{ "title" => "foo", "description" => "bar" }]
        )
        expect(entry.raif_model_completions.count).to eq(2)
        expect(entry.raif_model_completion).to eq(entry.raif_model_completions.order(:created_at).last)

        second_attempt_messages = entry.raif_model_completions.order(:created_at).last.messages
        feedback_message = second_attempt_messages.last
        feedback_json = feedback_message.to_json

        expect(feedback_message["role"]).to eq("user")
        expect(feedback_json).to include("invalid tool call")
        expect(feedback_json).to include("test_model_tool")
        expect(feedback_json).to include("Expected arguments schema")
        expect(feedback_json).to include("Available tools:")
        # Only the messages from this attempt — the retry feedback is NOT a
        # ToolCall replay (would break providers that expect valid JSON args)
        # and it is NOT persisted into conversation history.
        expect(second_attempt_messages.any? { |m| m["type"] == "tool_call" }).to be(false)
        expect(attempts).to eq(2)

        # Synthetic feedback does not leak into the persisted conversation history.
        expect(conversation.llm_messages.to_json).not_to include("invalid tool call")
      end

      it "fails after exhausting the retry budget when tool calls remain invalid and logs ModelCompletion id + retry budget" do
        allow(Raif.config).to receive(:conversation_entry_max_retries).and_return(1)

        attempts = 0
        stub_raif_conversation(conversation) do |_messages, model_completion|
          attempts += 1
          model_completion.response_tool_calls = invalid_tool_call
          ""
        end

        log_pattern = /Raif::ConversationEntry ##{entry.id} failed after exhausting conversation_entry_max_retries=1 retries\. ModelCompletion #\d+ returned invalid tool calls: \{tool="test_model_tool" status=non_hash_arguments/ # rubocop:disable Layout/LineLength
        expect(Raif.logger).to receive(:error).with(log_pattern).at_least(:once)
        allow(Raif.logger).to receive(:error).and_call_original

        entry.process_entry!

        expect(entry.reload).to be_failed
        expect(entry.raif_model_tool_invocations.count).to eq(0)
        expect(attempts).to eq(2)
        expect(entry.raif_model_completions.count).to eq(2)
      end
    end

    context "when the response includes multiple tool calls, only some of which are invalid" do
      it "invokes none of them before retrying and only invokes on a fully-valid retry" do
        attempts = 0
        stub_raif_conversation(conversation) do |_messages, model_completion|
          attempts += 1
          model_completion.response_tool_calls = if attempts == 1
            [
              {
                "provider_tool_call_id" => "tooluse_ok_first",
                "name" => "test_model_tool",
                "arguments" => { "items" => [{ "title" => "foo", "description" => "bar" }] }
              },
              {
                "provider_tool_call_id" => "tooluse_bad",
                "name" => "test_model_tool",
                "arguments" => "not-valid-json"
              }
            ]
          else
            [
              {
                "provider_tool_call_id" => "tooluse_ok_1",
                "name" => "test_model_tool",
                "arguments" => { "items" => [{ "title" => "a", "description" => "b" }] }
              },
              {
                "provider_tool_call_id" => "tooluse_ok_2",
                "name" => "test_model_tool",
                "arguments" => { "items" => [{ "title" => "c", "description" => "d" }] }
              }
            ]
          end

          "ok"
        end

        entry.process_entry!

        expect(entry.reload).to be_completed
        expect(entry.raif_model_tool_invocations.count).to eq(2)
        expect(entry.raif_model_tool_invocations.pluck(:provider_tool_call_id)).to match_array(["tooluse_ok_1", "tooluse_ok_2"])
      end
    end

    context "when the response is an unknown tool name" do
      it "retries with synthetic feedback and succeeds when the model corrects the name" do
        attempts = 0
        stub_raif_conversation(conversation) do |_messages, model_completion|
          attempts += 1
          model_completion.response_tool_calls = if attempts == 1
            [{
              "name" => "not_a_real_tool",
              "arguments" => { "items" => [{ "title" => "foo", "description" => "bar" }] }
            }]
          else
            [{
              "name" => "test_model_tool",
              "arguments" => { "items" => [{ "title" => "foo", "description" => "bar" }] }
            }]
          end
          ""
        end

        entry.process_entry!

        expect(entry.reload).to be_completed
        expect(entry.raif_model_tool_invocations.count).to eq(1)
        expect(attempts).to eq(2)
      end
    end

    context "when the response has valid tool arguments (no retry)" do
      it "completes with a single model completion and no retry" do
        attempts = 0
        stub_raif_conversation(conversation) do |_messages, model_completion|
          attempts += 1
          model_completion.response_tool_calls = [{
            "name" => "test_model_tool",
            "arguments" => { "items" => [{ "title" => "foo", "description" => "bar" }] }
          }]
          "ok"
        end

        entry.process_entry!

        expect(entry.reload).to be_completed
        expect(attempts).to eq(1)
        expect(entry.raif_model_completions.count).to eq(1)
      end
    end

    context "when the response is a direct answer with no tool calls" do
      it "does not retry — a no-tool-call response is always valid" do
        attempts = 0
        stub_raif_conversation(conversation) do |_messages, model_completion|
          attempts += 1
          model_completion.response_tool_calls = nil
          "Just answering directly"
        end

        entry.process_entry!

        expect(entry.reload).to be_completed
        expect(entry.model_response_message).to eq("Just answering directly")
        expect(attempts).to eq(1)
        expect(entry.raif_model_completions.count).to eq(1)
        expect(entry.raif_model_tool_invocations.count).to eq(0)
      end
    end

    context "when process_model_response_message raises on a retry attempt" do
      it "still marks the entry failed rather than leaving it generating forever" do
        attempts = 0
        stub_raif_conversation(conversation) do |_messages, model_completion|
          attempts += 1
          model_completion.response_tool_calls = [{
            "name" => "test_model_tool",
            "arguments" => "not-valid-json"
          }]
          ""
        end

        allow_any_instance_of(Raif::TestConversation)
          .to receive(:process_model_response_message)
          .and_raise(RuntimeError, "boom")

        expect { entry.process_entry! }.not_to raise_error

        expect(entry.reload).to be_failed
      end
    end

    context "on_entry_finalized hook" do
      it "fires exactly once per successful finalize (not per streaming chunk, not per retry)" do
        attempts = 0
        stub_raif_conversation(conversation) do |_messages, model_completion|
          attempts += 1
          model_completion.response_tool_calls = if attempts == 1
            [{
              "name" => "test_model_tool",
              "arguments" => "garbage"
            }]
          else
            [{
              "name" => "test_model_tool",
              "arguments" => { "items" => [{ "title" => "ok", "description" => "ok" }] }
            }]
          end
          ""
        end

        hook_calls = []
        allow_any_instance_of(Raif::TestConversation).to receive(:on_entry_finalized) do |_, entry:|
          hook_calls << entry.id
        end

        entry.process_entry!

        expect(entry.reload).to be_completed
        expect(attempts).to eq(2)
        expect(hook_calls).to eq([entry.id])
      end

      it "does not fire for entries that exhaust retries and fail" do
        allow(Raif.config).to receive(:conversation_entry_max_retries).and_return(0)

        stub_raif_conversation(conversation) do |_messages, model_completion|
          model_completion.response_tool_calls = [{
            "name" => "test_model_tool",
            "arguments" => "garbage"
          }]
          ""
        end

        expect_any_instance_of(Raif::TestConversation).not_to receive(:on_entry_finalized)

        entry.process_entry!

        expect(entry.reload).to be_failed
      end
    end

    context "when prompting fails after persisting a model completion" do
      let!(:model_completion) do
        Raif::ModelCompletion.create!(
          source: entry,
          llm_model_key: conversation.llm_model_key,
          model_api_name: "test-model",
          response_format: conversation.response_format.to_sym,
          available_model_tools: conversation.available_model_tools,
          messages: [],
          system_prompt: conversation.build_system_prompt
        )
      end

      before do
        allow(conversation).to receive(:prompt_model_for_entry_response).and_return(nil)
      end

      it "preserves the failed model completion row for debugging" do
        expect do
          entry.process_entry!
        end.not_to change { Raif::ModelCompletion.where(id: model_completion.id).count }

        expect(entry.reload).to be_failed
        expect(entry.raif_model_completion).to eq(model_completion)
      end
    end
  end
end
