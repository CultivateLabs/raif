# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::PromptStudio::Tasks", type: :feature do
  let(:creator) { FB.create(:raif_test_user) }

  describe "index page" do
    let!(:completed_task) { FB.create(:raif_test_task, :completed, creator: creator) }
    let!(:incomplete_task) { FB.create(:raif_test_task, creator: creator) }

    it "displays a type selector and lists completed tasks when filtered" do
      visit raif.admin_prompt_studio_tasks_path

      expect(page).to have_content(I18n.t("raif.admin.prompt_studio.common.prompt_studio"))
      expect(page).to have_select("task_type")

      # No table shown before filtering
      expect(page).not_to have_css("table")

      # Filter by type
      select "Raif::TestTask", from: "task_type"
      click_button I18n.t("raif.admin.common.filter")

      # Only completed tasks shown
      expect(page).to have_css("table tbody tr", count: 1)
      within("table tbody") do
        expect(page).to have_content(completed_task.id.to_s)
        expect(page).not_to have_content(incomplete_task.id.to_s)
      end
    end

    it "shows empty state when no instances exist for type" do
      Raif::Task.destroy_all
      visit raif.admin_prompt_studio_tasks_path(task_type: "Raif::TestTask")

      expect(page).to have_content(I18n.t("raif.admin.prompt_studio.common.no_instances"))
    end
  end

  describe "show page" do
    let!(:task) do
      FB.create(:raif_test_task, :completed, creator: creator, system_prompt: "You are a test assistant.")
    end

    it "displays task details and prompt comparison" do
      visit raif.admin_prompt_studio_task_path(task)

      expect(page).to have_content(I18n.t("raif.admin.prompt_studio.tasks.show.page_title", id: task.id))
      expect(page).to have_content(task.type)
      expect(page).to have_content(task.llm_model_key)

      # Back link goes to filtered index
      expect(page).to have_link(
        I18n.t("raif.admin.prompt_studio.common.back"),
        href: raif.admin_prompt_studio_tasks_path(task_type: task.type)
      )

      # Prompt comparison section present
      expect(page).to have_content(I18n.t("raif.admin.common.prompt"))
      expect(page).to have_content(task.prompt)

      # Response section
      expect(page).to have_content(task.raw_response)
    end

    context "when prompt_studio_runs_enabled" do
      before { allow(Raif.config).to receive(:prompt_studio_runs_enabled).and_return(true) }

      it "shows the rerun form" do
        visit raif.admin_prompt_studio_task_path(task)

        expect(page).to have_content(I18n.t("raif.admin.prompt_studio.tasks.rerun.title"))
        expect(page).to have_select("llm_model_key")
        expect(page).to have_button(I18n.t("raif.admin.prompt_studio.tasks.rerun.submit"))
      end
    end

    context "when prompt_studio_runs_disabled" do
      before { allow(Raif.config).to receive(:prompt_studio_runs_enabled).and_return(false) }

      it "does not show the rerun form" do
        visit raif.admin_prompt_studio_task_path(task)

        expect(page).not_to have_content(I18n.t("raif.admin.prompt_studio.tasks.rerun.title"))
      end
    end

    context "when task is a prompt studio run" do
      let!(:task) do
        FB.create(:raif_test_task, :completed, creator: creator, prompt_studio_run: true)
      end

      it "shows the prompt studio run badge" do
        visit raif.admin_prompt_studio_task_path(task)

        expect(page).to have_content(I18n.t("raif.admin.prompt_studio.common.run_in_prompt_studio"))
      end
    end
  end
end
