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
    expect(Turbo::StreamsChannel).to receive(:broadcast_render_to).exactly(1).times.and_call_original

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

  it "supports conversations with html response format", js: true, vcr: { cassette_name: "open_ai_responses/html_response_format_conversation" } do
    allow(Raif.config).to receive(:conversation_types).and_return(["Raif::Conversations::HtmlConversationWithTools"])
    allow_any_instance_of(Raif::Conversation).to receive(:default_llm_model_key).and_return(:open_ai_responses_gpt_4_1_mini)

    visit chat_path(conversation_type: "html")
    expect(page).to have_content("What can I write you a song about?")

    fill_in "conversation_entry_user_message", with: "Can you please write me a song in the style of the Beatles?"

    expect do
      click_button "Send"
    end.to have_enqueued_job(Raif::ConversationEntryJob)
      .and change(Raif::ConversationEntry, :count).by(1)

    perform_enqueued_jobs

    conversation = Raif::Conversation.last
    expect(conversation.entries.count).to eq(1)

    entry = conversation.entries.last

    song = <<~SONG
      Title: "Sunshine in the Rain"
      Verse 1:
      Woke up this morning, sky was grey,
      But I felt a tune that chased away,
      All the clouds that hung so low,
      Like a secret only I could know.
      Chorus:
      Sunshine in the rain, dancing in my mind,
      Every little moment, love’s the tie that binds,
      Hand in hand we’ll find, through the storm and pain,
      There’s a light that shines, sunshine in the rain.
      Verse 2:
      Whispered words in melodies,
      Floating on a gentle breeze,
      Time stands still and hearts align,
      In this song, you're forever mine.
      Chorus:
      Sunshine in the rain, dancing in my mind,
      Every little moment, love’s the tie that binds,
      Hand in hand we’ll find, through the storm and pain,
      There’s a light that shines, sunshine in the rain.
      Bridge:
      Oh, the world keeps turning, seasons come and go,
      But in your eyes, I see a glow,
      That keeps me warm, through cold and grey,
      Our song will never fade away.
      Chorus:
      Sunshine in the rain, dancing in my mind,
      Every little moment, love’s the tie that binds,
      Hand in hand we’ll find, through the storm and pain,
      There’s a light that shines, sunshine in the rain.
    SONG

    expect(page).to have_content(song)

    expect(entry.user_message).to eq("Can you please write me a song in the style of the Beatles?")
    expect(entry.model_response_message).to eq("<p><strong>Title: \"Sunshine in the Rain\"</strong></p><p><em>Verse 1:</em></p><p>Woke up this morning, sky was grey,</p><p>But I felt a tune that chased away,</p><p>All the clouds that hung so low,</p><p>Like a secret only I could know.</p><p><em>Chorus:</em></p><p>Sunshine in the rain, dancing in my mind,</p><p>Every little moment, love’s the tie that binds,</p><p>Hand in hand we’ll find, through the storm and pain,</p><p>There’s a light that shines, sunshine in the rain.</p><p><em>Verse 2:</em></p><p>Whispered words in melodies,</p><p>Floating on a gentle breeze,</p><p>Time stands still and hearts align,</p><p>In this song, you're forever mine.</p><p><em>Chorus:</em></p><p>Sunshine in the rain, dancing in my mind,</p><p>Every little moment, love’s the tie that binds,</p><p>Hand in hand we’ll find, through the storm and pain,</p><p>There’s a light that shines, sunshine in the rain.</p><p><em>Bridge:</em></p><p>Oh, the world keeps turning, seasons come and go,</p><p>But in your eyes, I see a glow,</p><p>That keeps me warm, through cold and grey,</p><p>Our song will never fade away.</p><p><em>Chorus:</em></p><p>Sunshine in the rain, dancing in my mind,</p><p>Every little moment, love’s the tie that binds,</p><p>Hand in hand we’ll find, through the storm and pain,</p><p>There’s a light that shines, sunshine in the rain.</p>") # rubocop:disable Layout/LineLength
  end

  it "displays conversations index" do
    user = FB.create(:raif_test_user)
    conversation1 = FB.create(:raif_conversation, creator: user, created_at: 2.days.ago)
    conversation2 = FB.create(:raif_conversation, creator: user, created_at: 1.day.ago)
    FB.create(:raif_conversation_entry, raif_conversation: conversation1)
    FB.create(:raif_conversation_entry, raif_conversation: conversation1)
    FB.create(:raif_conversation_entry, raif_conversation: conversation2)

    allow_any_instance_of(Raif::ApplicationController).to receive(:raif_current_user).and_return(user)

    visit raif.conversations_path

    expect(page).to have_content("Past Conversations")
    expect(page).to have_content("Started")
    expect(page).to have_content("Actions")
    expect(page).to have_selector("a", text: "View", count: 2)

    first("a", text: "View").click

    expect(page).to have_content("Hello, how can I help you today?")
  end

  it "shows empty state when no conversations exist" do
    user = FB.create(:raif_test_user)
    allow_any_instance_of(Raif::ApplicationController).to receive(:raif_current_user).and_return(user)

    visit raif.conversations_path

    expect(page).to have_content("Past Conversations")
    expect(page).to have_content("No conversations found.")
    expect(page).not_to have_selector("table")
  end
end
