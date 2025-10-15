# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Config", type: :feature do
  describe "show page" do
    it "displays the Raif configuration settings" do
      visit raif.admin_config_path

      # Check page title
      expect(page).to have_content(I18n.t("raif.admin.config.show.title"))

      # Check for category headers
      expect(page).to have_content("API Keys")
      expect(page).to have_content("LLM Providers")
      expect(page).to have_content("Default Models")

      # Check for column headers
      expect(page).to have_content(I18n.t("raif.admin.config.show.setting"))
      expect(page).to have_content(I18n.t("raif.admin.config.show.value"))

      # Check that sensitive keys are masked
      expect(page).to have_content("open_ai_api_key")
      expect(page).to have_content("anthropic_api_key")
      # API keys should be masked with asterisks or show "Not set"
      expect(page).to have_css("code.text-muted", text: /\*+/) || have_content("Not set")

      # Check for LLM registry section
      expect(page).to have_content(I18n.t("raif.admin.config.show.registered_llms"))
      expect(page).to have_content(I18n.t("raif.admin.config.show.key"))
      expect(page).to have_content(I18n.t("raif.admin.common.class"))

      # Check for embedding models section
      expect(page).to have_content(I18n.t("raif.admin.config.show.registered_embedding_models"))
    end

    it "masks API keys properly" do
      # Temporarily set an API key for testing
      allow(Raif.config).to receive(:open_ai_api_key).and_return("sk-test-1234567890abcdef")
      visit raif.admin_config_path

      # Should show first 5 chars + asterisks
      expect(page).to have_content("sk-te********************")
    end

    it "displays default model badges" do
      visit raif.admin_config_path

      # The default LLM model should have a "default" badge
      within(".card") do
        if Raif.llm_registry.any?
          expect(page).to have_css("span.badge", text: I18n.t("raif.admin.config.show.default"))
        end
      end
    end
  end
end
