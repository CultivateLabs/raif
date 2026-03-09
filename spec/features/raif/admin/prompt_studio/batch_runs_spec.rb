# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::PromptStudio::BatchRuns", type: :feature do
  let(:creator) { FB.create(:raif_test_user) }

  describe "tasks index with batch form" do
    let!(:task1) { FB.create(:raif_test_task, :completed, creator: creator) }
    let!(:task2) { FB.create(:raif_test_task, :completed, creator: creator) }

    context "when prompt_studio_runs_enabled" do
      before { allow(Raif.config).to receive(:prompt_studio_runs_enabled).and_return(true) }

      it "shows checkboxes and batch run button" do
        visit raif.admin_prompt_studio_tasks_path(task_type: "Raif::TestTask")

        expect(page).to have_css("[data-raif--select-all-checkboxes-target='selectAll']")
        expect(page).to have_css(".task-checkbox", count: 2)
        expect(page).to have_button(I18n.t("raif.admin.prompt_studio.batch_runs.create.new_batch_run"), disabled: true)
      end

      it "shows batch run modal with judge configuration" do
        visit raif.admin_prompt_studio_tasks_path(task_type: "Raif::TestTask")

        expect(page).to have_css("#batch-run-modal", visible: :all)
        expect(page).to have_button(I18n.t("raif.admin.prompt_studio.batch_runs.create.submit"), visible: :all)
        expect(page).to have_select("judge_type", visible: :all)
      end
    end

    context "when prompt_studio_runs_disabled" do
      before { allow(Raif.config).to receive(:prompt_studio_runs_enabled).and_return(false) }

      it "does not show checkboxes or batch form" do
        visit raif.admin_prompt_studio_tasks_path(task_type: "Raif::TestTask")

        expect(page).not_to have_css("[data-raif--select-all-checkboxes-target='selectAll']")
        expect(page).not_to have_css(".task-checkbox")
      end
    end
  end

  describe "show page" do
    let(:batch_run) { FB.create(:raif_prompt_studio_batch_run, total_count: 2, started_at: 1.minute.ago) }

    before do
      2.times do
        source_task = FB.create(:raif_test_task, :completed, creator: creator)
        batch_run.items.create!(source_task: source_task, status: "completed")
      end
      batch_run.update!(completed_count: 2, completed_at: Time.current)
    end

    it "renders batch run details with progress and items" do
      visit raif.admin_prompt_studio_batch_run_path(batch_run)

      expect(page).to have_content(I18n.t("raif.admin.prompt_studio.batch_runs.show.page_title", id: batch_run.id))
      expect(page).to have_content(I18n.t("raif.admin.prompt_studio.batch_runs.show.progress"))
      expect(page).to have_content("100%")
      expect(page).to have_css("table tbody tr", count: 2)
    end

    it "shows back link to tasks index" do
      visit raif.admin_prompt_studio_batch_run_path(batch_run)

      expect(page).to have_link(
        I18n.t("raif.admin.prompt_studio.common.back"),
        href: raif.admin_prompt_studio_tasks_path(task_type: batch_run.task_type)
      )
    end
  end
end
