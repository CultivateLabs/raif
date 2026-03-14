# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::PromptStudio::Conversations", type: :feature do
  let(:creator) { FB.create(:raif_test_user) }

  describe "index page" do
    let!(:conversations) { FB.create_list(:raif_test_conversation, 2, creator: creator) }

    it "displays a type selector and lists conversations when filtered" do
      visit raif.admin_prompt_studio_conversations_path

      expect(page).to have_content(I18n.t("raif.admin.prompt_studio.common.prompt_studio"))
      expect(page).to have_select("conversation_type")

      # No table shown before filtering
      expect(page).not_to have_css("table")

      # Filter by type
      select "Raif::TestConversation", from: "conversation_type"
      click_button I18n.t("raif.admin.common.filter")

      expect(page).to have_css("table tbody tr", count: 2)
    end

    it "shows empty state when no instances exist for type" do
      Raif::Conversation.destroy_all
      visit raif.admin_prompt_studio_conversations_path(conversation_type: "Raif::TestConversation")

      expect(page).to have_content(I18n.t("raif.admin.prompt_studio.common.no_instances"))
    end
  end

  describe "show page" do
    let!(:conversation) { FB.create(:raif_test_conversation, creator: creator) }

    before do
      # Ensure system_prompt is populated by triggering build
      conversation.update!(system_prompt: conversation.build_system_prompt)
    end

    it "displays conversation details and prompt comparison" do
      visit raif.admin_prompt_studio_conversation_path(conversation)

      expect(page).to have_content(I18n.t("raif.admin.prompt_studio.conversations.show.page_title", id: conversation.id))
      expect(page).to have_content(conversation.type)
      expect(page).to have_content(conversation.llm_model_key)

      # Back link goes to filtered index
      expect(page).to have_link(
        I18n.t("raif.admin.prompt_studio.common.back"),
        href: raif.admin_prompt_studio_conversations_path(conversation_type: conversation.type)
      )

      # System prompt comparison section present
      expect(page).to have_content(I18n.t("raif.admin.common.system_prompt"))
      expect(page).to have_content(conversation.system_prompt.first(100))
    end
  end
end
