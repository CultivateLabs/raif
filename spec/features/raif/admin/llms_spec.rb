# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Llms", type: :feature do
  describe "index page" do
    it "displays the registered LLMs with pricing information" do
      visit raif.admin_llms_path

      expect(page).to have_content("Registered LLMs")
      expect(page).to have_content("Name")
      expect(page).to have_content("Input Cost (per 1M tokens)")
      expect(page).to have_content("Output Cost (per 1M tokens)")

      # Should show at least one registered LLM
      Raif.llm_registry.each_key do |key|
        config = Raif.llm_config(key)
        llm_class = config[:llm_class]
        llm = llm_class.new(**config.except(:llm_class))
        expect(page).to have_content(llm.name)
        break # just check the first one is present
      end
    end

    it "badges deprecated LLMs" do
      Raif.register_llm(Raif::Llms::TestLlm, key: :admin_badge_test_llm, api_name: "admin-badge-test-llm",
        deprecated: true, retirement_date: Date.new(2026, 12, 1))

      visit raif.admin_llms_path

      expect(page).to have_content("Deprecated")
    ensure
      Raif.llm_registry.delete(:admin_badge_test_llm)
    end
  end
end
