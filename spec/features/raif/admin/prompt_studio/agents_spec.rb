# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::PromptStudio::Agents", type: :feature do
  let(:creator) { FB.create(:raif_test_user) }

  describe "index page" do
    let!(:agent) do
      FB.create(
        :raif_native_tool_calling_agent,
        creator: creator,
        task: "Test task",
        started_at: 2.minutes.ago,
        completed_at: 1.minute.ago
      )
    end

    it "displays a type selector and lists agents when filtered" do
      visit raif.admin_prompt_studio_agents_path

      expect(page).to have_content(I18n.t("raif.admin.prompt_studio.common.prompt_studio"))
      expect(page).to have_select("agent_type")

      # No table shown before filtering
      expect(page).not_to have_css("table")

      # Filter by type
      select "Raif::Agents::NativeToolCallingAgent", from: "agent_type"
      click_button I18n.t("raif.admin.common.filter")

      expect(page).to have_css("table tbody tr", count: 1)
      expect(page).to have_content(agent.id.to_s)
    end

    it "shows empty state when no instances exist for type" do
      Raif::Agent.destroy_all
      visit raif.admin_prompt_studio_agents_path(agent_type: "Raif::Agents::NativeToolCallingAgent")

      expect(page).to have_content(I18n.t("raif.admin.prompt_studio.common.no_instances"))
    end
  end

  describe "show page" do
    let!(:agent) do
      FB.create(
        :raif_native_tool_calling_agent,
        creator: creator,
        task: "What is the capital of France?",
        started_at: 2.minutes.ago,
        completed_at: 1.minute.ago,
        final_answer: "The capital of France is Paris."
      )
    end

    it "displays agent details and prompt comparison" do
      visit raif.admin_prompt_studio_agent_path(agent)

      expect(page).to have_content(I18n.t("raif.admin.prompt_studio.agents.show.page_title", id: agent.id))
      expect(page).to have_content(agent.type)
      expect(page).to have_content(agent.llm_model_key)

      # Back link goes to filtered index
      expect(page).to have_link(
        I18n.t("raif.admin.prompt_studio.common.back"),
        href: raif.admin_prompt_studio_agents_path(agent_type: agent.type)
      )

      # System prompt comparison section present
      expect(page).to have_content(I18n.t("raif.admin.common.system_prompt"))
      expect(page).to have_content(agent.system_prompt.first(100))

      # Task shown
      expect(page).to have_content("What is the capital of France?")

      # Final answer shown
      expect(page).to have_content("The capital of France is Paris.")
    end
  end
end
