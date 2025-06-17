# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Conversation interface", type: :feature do
  let(:creator) { FB.create(:raif_test_user) }

  it "displays the conversation interface", js: true do
    stub_raif_conversation(Raif::Conversation) do |_messages|
      "I'm great how are you?"
    end

    visit chat_path
    expect(page).to have_content("Hello, how can I help you today?")

    fill_in "conversation_entry_user_message", with: "How are you today?"
    expect do
      click_button "Send"
    end.to have_enqueued_job(Raif::ConversationEntryJob)
      .and change(Raif::ConversationEntry, :count).by(1)

    perform_enqueued_jobs

    expect(page).to have_content("I'm great how are you?")

    conversation = Raif::Conversation.last
    expect(conversation.entries.count).to eq(1)

    entry = conversation.entries.last
    user = Raif::TestUser.last
    expect(entry.user_message).to eq("How are you today?")
    expect(entry.model_response_message).to eq("I'm great how are you?")
    expect(entry.raw_response).to eq("I'm great how are you?")
    expect(entry).to be_completed
    expect(entry.creator).to eq(user)
    expect(entry.raif_user_tool_invocation).to be_nil
    expect(entry.raif_conversation).to eq(conversation)
    expect(entry.raif_model_completion).to be_present

    mc = entry.raif_model_completion
    expect(mc.model_api_name).to eq("raif-test-llm")
    expect(mc.llm_model_key).to eq("raif_test_llm")
    expect(mc.parsed_response).to eq("I'm great how are you?")
  end

  it "supports streaming conversations", js: true, vcr: { cassette_name: "open_ai_responses/streaming_conversation" } do
    allow_any_instance_of(Raif::Conversation).to receive(:default_llm_model_key).and_return(:open_ai_responses_gpt_4_1_mini)
    expect_any_instance_of(Raif::ConversationEntry).to receive(:broadcast_replace_to).with(Raif::Conversation).exactly(16).times.and_call_original

    visit chat_path
    expect(page).to have_content("Hello, how can I help you today?")

    fill_in "conversation_entry_user_message", with: "Can you please write me a 1 paragraph poem about forecasting?"
    expect do
      click_button "Send"
    end.to have_enqueued_job(Raif::ConversationEntryJob)
      .and change(Raif::ConversationEntry, :count).by(1)

    perform_enqueued_jobs

    expect(page).to have_content("Certainly! Here’s a one-paragraph poem about forecasting:")

    expect(page).to have_content("In whispers of the wind and charts aligned,")
    expect(page).to have_content("We seek the secrets time has yet defined,")
    expect(page).to have_content("A dance of numbers, patterns intertwined,")
    expect(page).to have_content("Forecasting dreams the future’s frame designed.")
    expect(page).to have_content("Through clouds of data, past and present cast,")
    expect(page).to have_content("We glimpse tomorrow’s shadow, bright or vast,")
    expect(page).to have_content("With hope and caution, visions hold us fast,")
    expect(page).to have_content("To navigate the moments as they pass.")

    conversation = Raif::Conversation.last
    expect(conversation.entries.count).to eq(1)

    entry = conversation.entries.last
    user = Raif::TestUser.last

    expect(entry.user_message).to eq("Can you please write me a 1 paragraph poem about forecasting?")
    expect(entry.model_response_message).to eq("Certainly! Here’s a one-paragraph poem about forecasting:\n\nIn whispers of the wind and charts aligned,  \nWe seek the secrets time has yet defined,  \nA dance of numbers, patterns intertwined,  \nForecasting dreams the future’s frame designed.  \nThrough clouds of data, past and present cast,  \nWe glimpse tomorrow’s shadow, bright or vast,  \nWith hope and caution, visions hold us fast,  \nTo navigate the moments as they pass.") # rubocop:disable Layout/LineLength
    expect(entry.raw_response).to eq("Certainly! Here’s a one-paragraph poem about forecasting:\n\nIn whispers of the wind and charts aligned,  \nWe seek the secrets time has yet defined,  \nA dance of numbers, patterns intertwined,  \nForecasting dreams the future’s frame designed.  \nThrough clouds of data, past and present cast,  \nWe glimpse tomorrow’s shadow, bright or vast,  \nWith hope and caution, visions hold us fast,  \nTo navigate the moments as they pass.") # rubocop:disable Layout/LineLength
    expect(entry).to be_completed
    expect(entry.creator).to eq(user)
    expect(entry.raif_user_tool_invocation).to be_nil
    expect(entry.raif_conversation).to eq(conversation)
    expect(entry.raif_model_completion).to be_present

    mc = entry.raif_model_completion
    expect(mc.model_api_name).to eq("gpt-4.1-mini")
    expect(mc.llm_model_key).to eq("open_ai_responses_gpt_4_1_mini")
    expect(mc.parsed_response).to eq("Certainly! Here’s a one-paragraph poem about forecasting:\n\nIn whispers of the wind and charts aligned,  \nWe seek the secrets time has yet defined,  \nA dance of numbers, patterns intertwined,  \nForecasting dreams the future’s frame designed.  \nThrough clouds of data, past and present cast,  \nWe glimpse tomorrow’s shadow, bright or vast,  \nWith hope and caution, visions hold us fast,  \nTo navigate the moments as they pass.") # rubocop:disable Layout/LineLength
    expect(mc.stream_response?).to eq(true)
  end
end
