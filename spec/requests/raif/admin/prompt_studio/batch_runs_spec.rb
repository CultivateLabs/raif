# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::PromptStudio::BatchRuns", type: :request do
  let(:creator) { FB.create(:raif_test_user) }

  describe "POST /admin/prompt_studio/batch_runs" do
    let!(:task1) { FB.create(:raif_test_task, :completed, creator: creator) }
    let!(:task2) { FB.create(:raif_test_task, :completed, creator: creator) }
    let(:llm_model_key) { Raif.available_llm_keys.first.to_s }

    def post_create(params = {})
      post raif.admin_prompt_studio_batch_runs_path, params: {
        task_type: "Raif::TestTask",
        llm_model_key: llm_model_key,
        source_task_ids: [task1.id, task2.id]
      }.merge(params)
    end

    context "when prompt_studio_runs_enabled" do
      before { allow(Raif.config).to receive(:prompt_studio_runs_enabled).and_return(true) }

      it "creates a batch run with items and enqueues the job" do
        expect do
          post_create
        end.to change(Raif::PromptStudioBatchRun, :count).by(1)
          .and change(Raif::PromptStudioBatchRunItem, :count).by(2)
          .and have_enqueued_job(Raif::PromptStudioBatchRunJob)

        batch_run = Raif::PromptStudioBatchRun.last
        expect(batch_run.task_type).to eq("Raif::TestTask")
        expect(batch_run.llm_model_key).to eq(llm_model_key)
        expect(batch_run.total_count).to eq(2)
        expect(batch_run.items.pluck(:source_task_id)).to contain_exactly(task1.id, task2.id)
        expect(response).to redirect_to(raif.admin_prompt_studio_batch_run_path(batch_run))
      end

      it "sets judge config for binary judge" do
        post_create(
          judge_type: "Raif::Evals::LlmJudges::Binary",
          judge_criteria: "Is accurate",
          judge_strict_mode: "1",
          judge_llm_model_key: llm_model_key
        )

        batch_run = Raif::PromptStudioBatchRun.last
        expect(batch_run.judge_type).to eq("Raif::Evals::LlmJudges::Binary")
        expect(batch_run.judge_config).to eq({ "criteria" => "Is accurate", "strict_mode" => true, "include_original_prompt_as_context" => false })
        expect(batch_run.judge_llm_model_key).to eq(llm_model_key)
      end

      it "sets judge config for scored judge" do
        post_create(
          judge_type: "Raif::Evals::LlmJudges::Scored",
          judge_scoring_rubric: "helpfulness",
          judge_llm_model_key: llm_model_key
        )

        batch_run = Raif::PromptStudioBatchRun.last
        expect(batch_run.judge_config).to eq({ "scoring_rubric" => "helpfulness", "include_original_prompt_as_context" => false })
      end

      it "sets judge config for comparative judge" do
        post_create(
          judge_type: "Raif::Evals::LlmJudges::Comparative",
          judge_comparison_criteria: "Which response better addresses the prompt",
          judge_llm_model_key: llm_model_key
        )

        batch_run = Raif::PromptStudioBatchRun.last
        expect(batch_run.judge_type).to eq("Raif::Evals::LlmJudges::Comparative")
        expect(batch_run.judge_config).to eq({
          "comparison_criteria" => "Which response better addresses the prompt",
          "include_original_prompt_as_context" => false
        })
      end

      it "sets judge config for summarization judge" do
        post_create(
          judge_type: "Raif::Evals::LlmJudges::Summarization",
          judge_llm_model_key: llm_model_key
        )

        batch_run = Raif::PromptStudioBatchRun.last
        expect(batch_run.judge_type).to eq("Raif::Evals::LlmJudges::Summarization")
        expect(batch_run.judge_config).to eq({ "include_original_prompt_as_context" => false })
      end

      it "stores include_original_prompt_as_context when checked" do
        post_create(
          judge_type: "Raif::Evals::LlmJudges::Binary",
          judge_criteria: "Is accurate",
          judge_include_original_prompt_as_context: "1",
          judge_llm_model_key: llm_model_key
        )

        batch_run = Raif::PromptStudioBatchRun.last
        expect(batch_run.judge_config["include_original_prompt_as_context"]).to be true
      end

      it "redirects with alert when no tasks selected" do
        post_create(source_task_ids: [])

        expect(response).to redirect_to(raif.admin_prompt_studio_tasks_path(task_type: "Raif::TestTask"))
        expect(flash[:alert]).to eq(I18n.t("raif.admin.prompt_studio.batch_runs.create.no_tasks_selected"))
      end
    end

    context "when prompt_studio_runs_disabled" do
      before { allow(Raif.config).to receive(:prompt_studio_runs_enabled).and_return(false) }

      it "redirects with alert and does not create a batch run" do
        expect { post_create }.not_to change(Raif::PromptStudioBatchRun, :count)

        expect(response).to redirect_to(raif.admin_prompt_studio_tasks_path)
        expect(flash[:alert]).to eq(I18n.t("raif.admin.prompt_studio.common.runs_disabled"))
      end
    end
  end

  describe "GET /admin/prompt_studio/batch_runs/:id" do
    let(:batch_run) { FB.create(:raif_prompt_studio_batch_run, total_count: 1) }

    before do
      source_task = FB.create(:raif_test_task, :completed, creator: creator)
      batch_run.items.create!(source_task: source_task)
    end

    it "renders the show page" do
      get raif.admin_prompt_studio_batch_run_path(batch_run)
      expect(response).to have_http_status(:success)
    end
  end
end
