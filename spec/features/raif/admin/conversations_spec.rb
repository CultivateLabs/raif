# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Conversations", type: :feature do
  let(:creator) { FB.create(:raif_test_user) }

  describe "index page" do
    let!(:conversations) { FB.create_list(:raif_test_conversation, 2, creator: creator) }
    let!(:conversation_with_entries) { FB.create(:raif_test_conversation, :with_entries, creator: creator) }

    it "displays conversations with all details and handles empty state" do
      visit raif.admin_conversations_path

      # Check page title and table headers
      expect(page).to have_content(I18n.t("raif.admin.common.conversations"))
      expect(page).to have_content(I18n.t("raif.admin.common.id"))
      expect(page).to have_content(I18n.t("raif.admin.common.created_at"))
      expect(page).to have_content(I18n.t("raif.admin.common.creator"))
      expect(page).to have_content(I18n.t("raif.admin.common.type"))
      expect(page).to have_content(I18n.t("raif.admin.common.entries_count"))

      # Check conversations count
      expect(page).to have_css("tr.raif-conversation", count: 3)

      # Check specific conversation details
      within("table tbody") do
        # Check conversation with entries
        expect(page).to have_content("##{conversation_with_entries.id}")
        expect(page).to have_content("3") # entries count
      end

      # Test navigation to conversation detail page
      click_link "##{conversation_with_entries.id}"
      expect(page).to have_current_path(raif.admin_conversation_path(conversation_with_entries))

      # Go back to index and test empty state
      visit raif.admin_conversations_path
      Raif::Conversation.delete_all
      visit raif.admin_conversations_path
      expect(page).to have_content(I18n.t("raif.admin.common.no_conversations"))
    end
  end

  describe "show page" do
    let!(:conversation){ FB.create(:raif_test_conversation, :with_entries, creator: creator) }

    it "displays the conversation details and entries" do
      expect(conversation.entries.count).to eq(3)
      conversation.entries.each do |entry|
        expect(entry.user_message).to be_present
        expect(entry.model_response_message).to be_present
      end

      visit raif.admin_conversation_path(conversation)

      expect(page).to have_content(I18n.t("raif.admin.conversations.show.title", id: conversation.id))

      # Check basic details
      expect(page).to have_content(conversation.id.to_s)
      expect(page).to have_content(conversation.creator_type)
      expect(page).to have_content(conversation.creator_id.to_s)
      expect(page).to have_content(conversation.type)
      expect(page).to have_content("3") # entries count

      # Check conversation entries
      conversation.entries.each do |entry|
        expect(page).to have_content(entry.user_message)
        expect(page).to have_content(entry.model_response_message)
      end

      # Check status badges
      expect(page).to have_css(".badge.bg-success", text: I18n.t("raif.admin.common.completed"), count: 3)

      expect(page).to have_link(I18n.t("raif.admin.conversations.show.back_to_conversations"), href: raif.admin_conversations_path)
    end
  end
end
