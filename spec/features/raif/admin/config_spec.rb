# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Config", type: :feature do
  describe "show page" do
    it "displays the Raif configuration settings" do
      allow(Raif.config).to receive(:open_ai_api_key).and_return("oai-key-1234567890abcdef")
      allow(Raif.config).to receive(:anthropic_api_key).and_return("an-key-1234567890abcdef")

      visit raif.admin_config_path

      # Check page title
      expect(page).to have_content("Raif Configuration")

      # Check that sensitive keys are masked
      expect(page).to have_content("open_ai_api_key")
      expect(page).to have_content("anthropic_api_key")

      # API key should be masked
      expect(page).to have_content("oai-k********************")
      expect(page).to have_content("an-ke********************")

      # Check for LLM registry section
      expect(page).to have_content(I18n.t("raif.admin.config.show.registered_llms"))
      expect(page).to have_content(I18n.t("raif.admin.config.show.key"))

      # Check for embedding models section
      expect(page).to have_content(I18n.t("raif.admin.config.show.registered_embedding_models"))
    end
  end
end
