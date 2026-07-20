# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Conversation entries creator scoping", type: :request do
  let(:victim) { FB.create(:raif_test_user) }
  let(:attacker) { FB.create(:raif_test_user) }
  let!(:victim_conversation) { FB.create(:raif_conversation, creator: victim) }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(attacker)
  end

  it "does not let an attacker open the new entry form on another user's conversation" do
    get "/raif/conversations/#{victim_conversation.id}/entries/new",
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:not_found)
  end

  it "does not let an attacker create an entry on another user's conversation by id" do
    post "/raif/conversations/#{victim_conversation.id}/entries",
      params: { conversation_entry: { user_message: "injected into victim conversation" } },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:not_found)
    expect(victim_conversation.entries.reload.count).to eq(0)
  end
end
