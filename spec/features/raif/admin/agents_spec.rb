# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Agents", type: :feature do
  let(:creator) { FB.create(:raif_test_user) }

  describe "index page" do
    let!(:pending_agent) do
      FB.create(
        :raif_native_tool_calling_agent,
        creator: creator,
        task: "What is the capital of France?",
        max_iterations: 5
      )
    end

    let!(:raif_agent) do
      FB.create(
        :raif_native_tool_calling_agent,
        creator: creator,
        task: "List the planets in our solar system",
        started_at: 2.minutes.ago,
        iteration_count: 2,
        max_iterations: 5
      )
    end

    let!(:completed_agent) do
      FB.create(
        :raif_native_tool_calling_agent,
        creator: creator,
        task: "Calculate 15 * 24",
        started_at: 5.minutes.ago,
        completed_at: 4.minutes.ago,
        iteration_count: 3,
        max_iterations: 5,
        final_answer: "The result of 15 * 24 is 360."
      )
    end

    let!(:failed_agent) do
      FB.create(
        :raif_native_tool_calling_agent,
        creator: creator,
        task: "This task will fail",
        started_at: 10.minutes.ago,
        failed_at: 9.minutes.ago,
        iteration_count: 1,
        max_iterations: 5
      )
    end

    let!(:long_task_agent) do
      FB.create(
        :raif_native_tool_calling_agent,
        creator: creator,
        task: "a" * 200,
        max_iterations: 10
      )
    end

    it "displays agents with all details and handles edge cases" do
      visit raif.admin_agents_path

      # Check page title and table headers
      expect(page).to have_content(I18n.t("raif.admin.common.agents"))
      expect(page).to have_content(I18n.t("raif.admin.common.id"))
      expect(page).to have_content(I18n.t("raif.admin.common.created_at"))
      expect(page).to have_content(I18n.t("raif.admin.common.task"))
      expect(page).to have_content(I18n.t("raif.admin.common.status"))
      expect(page).to have_content(I18n.t("raif.admin.common.iterations"))
      expect(page).to have_content(I18n.t("raif.admin.common.final_answer"))

      # Check agent count and status badges
      expect(page).to have_css("tr.raif-agent", count: 5) # Total number of agents
      expect(page).to have_css(".badge.bg-success", text: "Completed")
      expect(page).to have_css(".badge.bg-danger", text: "Failed")
      expect(page).to have_css(".badge.bg-warning", text: "Running")
      expect(page).to have_css(".badge.bg-secondary", text: "Pending")

      # Check iteration counts
      expect(page).to have_content("0 / 5") # pending_agent
      expect(page).to have_content("2 / 5") # raif_agent
      expect(page).to have_content("3 / 5") # completed_agent
      expect(page).to have_content("1 / 5") # failed_agent
      expect(page).to have_content("0 / 10") # long_task_agent

      # Check final answer
      expect(page).to have_content("The result of 15 * 24 is 360.")

      # Truncated long task
      expect(page).to have_content("a" * 97 + "...")

      # Test empty state
      Raif::Agent.destroy_all
      visit raif.admin_agents_path
      expect(page).to have_content(I18n.t("raif.admin.common.no_agents"))
    end
  end

  describe "show page" do
    let!(:agent) do
      FB.create(
        :raif_native_tool_calling_agent,
        creator: creator,
        task: "What is the capital of France?",
        started_at: 5.minutes.ago,
        completed_at: 4.minutes.ago,
        iteration_count: 2,
        max_iterations: 5,
        final_answer: "The capital of France is Paris.",
        llm_model_key: "open_ai_gpt_4o",
        conversation_history: [
          { role: "user", content: "What is the capital of France?" },
          { role: "assistant", content: "<thought>I need to determine the capital of France.</thought>" },
          { role: "assistant", content: "<answer>The capital of France is Paris.</answer>" }
        ]
      )
    end

    let!(:model_completion) do
      Raif::ModelCompletion.create!(
        source: agent,
        llm_model_key: "open_ai_gpt_4o",
        model_api_name: "gpt-4o",
        response_format: "text",
        raw_response: "<thought>I need to determine the capital of France.</thought>\n<answer>The capital of France is Paris.</answer>",
        total_tokens: 150
      )
    end

    before do
      visit raif.admin_agent_path(agent)
    end

    it "displays the agent details and has a back link to the index" do
      expect(page).to have_content(I18n.t("raif.admin.agents.show.title", id: agent.id))

      # Check basic details
      expect(page).to have_content(agent.id.to_s)
      expect(page).to have_content(agent.creator_type)
      expect(page).to have_content(agent.creator_id.to_s)
      expect(page).to have_content("open_ai_gpt_4o")

      # Check status
      expect(page).to have_css(".badge.bg-success", text: "Completed")
      expect(page).to have_content(agent.completed_at.rfc822)

      # Check iterations
      expect(page).to have_content("2 / 5")

      # Check task and final answer
      expect(page).to have_content("What is the capital of France?")
      expect(page).to have_content("The capital of France is Paris.")

      # Check system prompt
      expect(page).to have_content(agent.system_prompt.first(100))

      # Check conversation history
      expect(page).to have_content("What is the capital of France?")
      expect(page).to have_content("I need to determine the capital of France.")
      expect(page).to have_content("The capital of France is Paris.")

      # Check model completions section
      expect(page).to have_content(I18n.t("raif.admin.common.model_completions"))
      expect(page).to have_link("##{model_completion.id}", href: raif.admin_model_completion_path(model_completion))
      expect(page).to have_content(model_completion.created_at.rfc822)
      expect(page).to have_content("open_ai_gpt_4o")
      expect(page).to have_content("150")
      expect(page).to have_content("<thought>I need to determine the capital of France.</thought>")

      # Check back link functionality
      expect(page).to have_link(I18n.t("raif.admin.agents.show.back_to_agents"), href: raif.admin_agents_path)

      click_link I18n.t("raif.admin.agents.show.back_to_agents")
      expect(page).to have_current_path(raif.admin_agents_path)
    end
  end
end
