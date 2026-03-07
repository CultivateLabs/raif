# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::PromptStudio::Tasks", type: :request do
  let(:creator) { FB.create(:raif_test_user) }

  describe "POST /admin/prompt_studio/tasks" do
    let!(:task) { FB.create(:raif_test_task, :completed, creator: creator) }

    def post_create(llm_model_key: task.llm_model_key)
      post raif.admin_prompt_studio_tasks_path, params: { source_task_id: task.id, llm_model_key: llm_model_key }
    end

    context "when prompt_studio_runs_enabled" do
      before { allow(Raif.config).to receive(:prompt_studio_runs_enabled).and_return(true) }

      it "creates a new task with prompt_studio_run flag and redirects to it" do
        stub_raif_task(Raif::TestTask) { "Stubbed response" }

        expect { post_create }.to change(Raif::Task, :count).by(1)

        new_task = Raif::Task.last
        expect(new_task.prompt_studio_run?).to be true
        expect(new_task.type).to eq(task.type)
        expect(new_task.completed_at).to be_present
        expect(new_task.raw_response).to eq("Stubbed response")
        expect(response).to redirect_to(raif.admin_prompt_studio_task_path(new_task))
      end

      it "preserves run_with from the original task" do
        task.update!(run_with: { "topic" => "pirates" })

        stub_raif_task(Raif::TestTask) { "Stubbed response" }

        post_create

        new_task = Raif::Task.last
        expect(new_task.run_with).to eq({ "topic" => "pirates" })
      end

      it "allows selecting a different model" do
        other_key = (Raif.available_llm_keys.map(&:to_s) - [task.llm_model_key]).first
        stub_raif_task(Raif::TestTask) { "Different model response" }

        post_create(llm_model_key: other_key)

        new_task = Raif::Task.last
        expect(new_task.llm_model_key).to eq(other_key)
      end

      it "redirects with alert when model is invalid" do
        post_create(llm_model_key: "nonexistent_model")

        expect(response).to redirect_to(raif.admin_prompt_studio_task_path(task))
        expect(flash[:alert]).to eq(I18n.t("raif.admin.prompt_studio.tasks.rerun.invalid_model"))
      end

      it "redirects with alert when model is blank" do
        post_create(llm_model_key: "")

        expect(response).to redirect_to(raif.admin_prompt_studio_task_path(task))
        expect(flash[:alert]).to eq(I18n.t("raif.admin.prompt_studio.tasks.rerun.invalid_model"))
      end
    end

    context "when prompt_studio_runs_disabled" do
      before { allow(Raif.config).to receive(:prompt_studio_runs_enabled).and_return(false) }

      it "redirects with alert and does not create a task" do
        expect { post_create }.not_to change(Raif::Task, :count)

        expect(response).to redirect_to(raif.admin_prompt_studio_task_path(task))
        expect(flash[:alert]).to eq(I18n.t("raif.admin.prompt_studio.common.runs_disabled"))
      end
    end
  end
end
