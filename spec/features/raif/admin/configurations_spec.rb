# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Configurations", type: :feature do
  describe "index page" do
    it "displays the Raif configuration settings" do
      visit raif.admin_configurations_path

      # Check page title
      expect(page).to have_content(I18n.t("raif.admin.configurations.index.title"))

      # Check for category headers
      expect(page).to have_content("API Keys")
      expect(page).to have_content("LLM Providers")
      expect(page).to have_content("Default Models")

      # Check for column headers
      expect(page).to have_content(I18n.t("raif.admin.configurations.index.setting"))
      expect(page).to have_content(I18n.t("raif.admin.configurations.index.value"))

      # Check that sensitive keys are masked
      expect(page).to have_content("open_ai_api_key")
      expect(page).to have_content("anthropic_api_key")
      # API keys should be masked with asterisks or show "Not set"
      expect(page).to have_css("code.text-muted", text: /\*+/) || have_content("Not set")

      # Check for LLM registry section
      expect(page).to have_content(I18n.t("raif.admin.configurations.index.registered_llms"))
      expect(page).to have_content(I18n.t("raif.admin.configurations.index.key"))
      expect(page).to have_content(I18n.t("raif.admin.common.class"))

      # Check for embedding models section
      expect(page).to have_content(I18n.t("raif.admin.configurations.index.registered_embedding_models"))
    end

    it "masks API keys properly" do
      # Temporarily set an API key for testing
      allow(Raif.config).to receive(:open_ai_api_key).and_return("sk-test-1234567890abcdef")
      visit raif.admin_configurations_path

      # Should show first 5 chars + asterisks
      expect(page).to have_content("sk-te********************")
    end

    it "displays default model badges" do
      visit raif.admin_configurations_path

      # The default LLM model should have a "default" badge
      within(".card") do
        if Raif.llm_registry.any?
          expect(page).to have_css("span.badge", text: I18n.t("raif.admin.configurations.index.default"))
        end
      end
    end
  end
end
