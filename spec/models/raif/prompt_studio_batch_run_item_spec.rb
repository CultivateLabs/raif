# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_prompt_studio_batch_run_items
#
#  id             :bigint           not null, primary key
#  status         :string           default("pending"), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  batch_run_id   :bigint           not null
#  judge_task_id  :bigint
#  result_task_id :bigint
#  source_task_id :bigint           not null
#
# Indexes
#
#  index_raif_prompt_studio_batch_run_items_on_batch_run_id  (batch_run_id)
#  index_raif_prompt_studio_batch_run_items_on_status        (status)
#
# Foreign Keys
#
#  fk_rails_...  (batch_run_id => raif_prompt_studio_batch_runs.id)
#  fk_rails_...  (judge_task_id => raif_tasks.id)
#  fk_rails_...  (result_task_id => raif_tasks.id)
#  fk_rails_...  (source_task_id => raif_tasks.id)
#
require "rails_helper"

RSpec.describe Raif::PromptStudioBatchRunItem, type: :model do
  let(:creator) { FB.create(:raif_test_user) }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "validations" do
    it "validates status inclusion" do
      item = FB.build(:raif_prompt_studio_batch_run_item)
      item.status = "invalid"
      expect(item).not_to be_valid
      expect(item.errors[:status]).to be_present
    end

    it "accepts all valid statuses" do
      Raif::PromptStudioBatchRunItem::STATUSES.each do |s|
        item = FB.build(:raif_prompt_studio_batch_run_item, status: s)
        expect(item).to be_valid
      end
    end
  end

  describe "#execute!" do
    let(:batch_run) { FB.create(:raif_prompt_studio_batch_run, total_count: 1) }
    let(:source_task) { FB.create(:raif_test_task, :completed, creator: creator, run_with: { "topic" => "cats" }) }
    let!(:item) { batch_run.items.create!(source_task: source_task) }

    context "without a judge" do
      before do
        stub_raif_task(Raif::TestTask) { |_messages, _mc, _task| "new response" }
      end

      it "creates a new task from the source, runs it, and marks the item completed" do
        expect { item.execute! }.to change(Raif::Task, :count).by(1)

        item.reload
        expect(item.status).to eq("completed")
        expect(item.result_task).to be_present
        expect(item.result_task.prompt_studio_run?).to be true
        expect(item.result_task.llm_model_key).to eq(batch_run.llm_model_key)
        expect(item.result_task.raw_response).to eq("new response")
      end

      it "preserves run_with from the source task" do
        item.execute!
        expect(item.reload.result_task.run_with).to eq({ "topic" => "cats" })
      end

      it "updates the batch run completion state" do
        item.execute!
        batch_run.reload
        expect(batch_run.completed_count).to eq(1)
        expect(batch_run.completed_at).to be_present
      end
    end

    context "with a binary judge" do
      let(:batch_run) do
        FB.create(:raif_prompt_studio_batch_run, :with_judge_binary, total_count: 1)
      end

      before do
        stub_raif_task(Raif::TestTask) { |_messages, _mc, _task| "new response" }
        stub_raif_task(Raif::Evals::LlmJudges::Binary) do |_messages, _mc, _task|
          '{"passes": true, "reasoning": "Good response", "confidence": 0.9}'
        end
      end

      it "runs the binary judge and saves the judge task" do
        item.execute!

        item.reload
        expect(item.status).to eq("completed")
        expect(item.judge_task_id).to be_present
        expect(item.judge_task.type).to eq("Raif::Evals::LlmJudges::Binary")
      end
    end

    context "with a scored judge" do
      let(:batch_run) do
        FB.create(:raif_prompt_studio_batch_run, :with_judge_scored, total_count: 1)
      end

      before do
        stub_raif_task(Raif::TestTask) { |_messages, _mc, _task| "new response" }
        stub_raif_task(Raif::Evals::LlmJudges::Scored) do |_messages, _mc, _task|
          '{"score": 4, "reasoning": "Well done", "confidence": 0.85}'
        end
      end

      it "runs the scored judge and saves the judge task" do
        item.execute!

        item.reload
        expect(item.status).to eq("completed")
        expect(item.judge_task_id).to be_present
        expect(item.judge_task.type).to eq("Raif::Evals::LlmJudges::Scored")
      end
    end

    context "with a comparative judge" do
      let(:batch_run) do
        FB.create(
          :raif_prompt_studio_batch_run,
          judge_type: "Raif::Evals::LlmJudges::Comparative",
          judge_config: { "comparison_criteria" => "Which response better addresses the prompt" },
          judge_llm_model_key: Raif.available_llm_keys.first.to_s,
          total_count: 1
        )
      end

      before do
        stub_raif_task(Raif::TestTask) { |_messages, _mc, _task| "new response" }
        stub_raif_task(Raif::Evals::LlmJudges::Comparative) do |_messages, _mc, _task|
          '{"winner": "A", "reasoning": "More detailed", "confidence": 0.8}'
        end
      end

      it "runs the comparative judge with both the new and original responses" do
        item.execute!

        item.reload
        expect(item.status).to eq("completed")
        expect(item.judge_task_id).to be_present
        expect(item.judge_task.type).to eq("Raif::Evals::LlmJudges::Comparative")
      end
    end

    context "with a summarization judge" do
      let(:batch_run) do
        FB.create(
          :raif_prompt_studio_batch_run,
          judge_type: "Raif::Evals::LlmJudges::Summarization",
          judge_config: {},
          judge_llm_model_key: Raif.available_llm_keys.first.to_s,
          total_count: 1
        )
      end

      before do
        stub_raif_task(Raif::TestTask) { |_messages, _mc, _task| "summarized response" }
        stub_raif_task(Raif::Evals::LlmJudges::Summarization) do |_messages, _mc, _task|
          {
            coverage: { justification: "ok", score: 4 },
            accuracy: { justification: "ok", score: 4 },
            clarity: { justification: "ok", score: 4 },
            conciseness: { justification: "ok", score: 4 },
            overall: { justification: "ok", score: 4 }
          }.to_json
        end
      end

      it "runs the summarization judge using source prompt as original content" do
        item.execute!

        item.reload
        expect(item.status).to eq("completed")
        expect(item.judge_task_id).to be_present
        expect(item.judge_task.type).to eq("Raif::Evals::LlmJudges::Summarization")
      end
    end

    context "with include_original_prompt_as_context enabled" do
      let(:batch_run) do
        FB.create(
          :raif_prompt_studio_batch_run,
          :with_judge_binary,
          judge_config: { "criteria" => "Is accurate", "include_original_prompt_as_context" => true },
          total_count: 1
        )
      end

      before do
        stub_raif_task(Raif::TestTask) { |_messages, _mc, _task| "new response" }
        stub_raif_task(Raif::Evals::LlmJudges::Binary) do |_messages, _mc, _task|
          '{"passes": true, "reasoning": "Good", "confidence": 0.9}'
        end
      end

      it "passes the source task prompt as additional context to the judge" do
        item.execute!

        item.reload
        judge = item.judge_task
        expect(judge.additional_context).to include(source_task.prompt)
        expect(judge.additional_context).to include("generated in response to the following prompt")
      end
    end

    context "when the task fails" do
      before do
        allow_any_instance_of(Raif::TestTask).to receive(:run).and_raise(StandardError, "LLM error")
      end

      it "marks the item as failed and still updates batch run completion" do
        item.execute!

        item.reload
        expect(item.status).to eq("failed")
        expect(batch_run.reload.failed_count).to eq(1)
      end
    end
  end

  describe "#judge_summary" do
    let(:batch_run) { FB.create(:raif_prompt_studio_batch_run, :with_judge_binary) }
    let(:source_task) { FB.create(:raif_test_task, :completed, creator: creator) }
    let(:item) { batch_run.items.create!(source_task: source_task) }

    it "returns nil when no judge_task" do
      expect(item.judge_summary).to be_nil
    end

    context "with binary judge" do
      it "returns PASS when judge passes" do
        judge = FB.create(
          :raif_test_task,
          :completed,
          creator: creator,
          response_format: :json,
          raw_response: '{"passes": true, "reasoning": "Good", "confidence": 0.9}',
          type: "Raif::Evals::LlmJudges::Binary"
        )
        item.update!(judge_task: judge)

        expect(item.judge_summary).to eq("PASS")
      end

      it "returns FAIL when judge fails" do
        judge = FB.create(
          :raif_test_task,
          :completed,
          creator: creator,
          response_format: :json,
          raw_response: '{"passes": false, "reasoning": "Bad", "confidence": 0.9}',
          type: "Raif::Evals::LlmJudges::Binary"
        )
        item.update!(judge_task: judge)

        expect(item.judge_summary).to eq("FAIL")
      end
    end

    context "with scored judge" do
      let(:batch_run) { FB.create(:raif_prompt_studio_batch_run, :with_judge_scored) }

      it "returns score" do
        judge = FB.create(
          :raif_test_task,
          :completed,
          creator: creator,
          response_format: :json,
          raw_response: '{"score": 4, "reasoning": "Good", "confidence": 0.9}',
          type: "Raif::Evals::LlmJudges::Scored"
        )
        item.update!(judge_task: judge)

        expect(item.judge_summary).to eq("Score: 4")
      end
    end

    context "with comparative judge" do
      let(:batch_run) do
        FB.create(
          :raif_prompt_studio_batch_run,
          judge_type: "Raif::Evals::LlmJudges::Comparative",
          judge_config: { "comparison_criteria" => "Which is better" }
        )
      end

      it "returns winner" do
        judge = FB.create(
          :raif_test_task,
          :completed,
          creator: creator,
          response_format: :json,
          raw_response: '{"winner": "A", "reasoning": "Better", "confidence": 0.9}',
          type: "Raif::Evals::LlmJudges::Comparative"
        )
        item.update!(judge_task: judge)

        expect(item.judge_summary).to eq("Winner: A")
      end

      it "returns Tie" do
        judge = FB.create(
          :raif_test_task,
          :completed,
          creator: creator,
          response_format: :json,
          raw_response: '{"winner": "tie", "reasoning": "Equal", "confidence": 0.9}',
          type: "Raif::Evals::LlmJudges::Comparative"
        )
        item.update!(judge_task: judge)

        expect(item.judge_summary).to eq("Tie")
      end
    end

    context "with summarization judge" do
      let(:batch_run) do
        FB.create(
          :raif_prompt_studio_batch_run,
          judge_type: "Raif::Evals::LlmJudges::Summarization",
          judge_config: {}
        )
      end

      it "returns overall score" do
        summarization_response = {
          coverage: { justification: "ok", score: 4 },
          accuracy: { justification: "ok", score: 4 },
          clarity: { justification: "ok", score: 4 },
          conciseness: { justification: "ok", score: 4 },
          overall: { justification: "ok", score: 4 }
        }.to_json

        judge = FB.create(
          :raif_test_task,
          :completed,
          creator: creator,
          response_format: :json,
          raw_response: summarization_response,
          type: "Raif::Evals::LlmJudges::Summarization"
        )
        item.update!(judge_task: judge)

        expect(item.judge_summary).to eq("Overall: 4/5")
      end
    end
  end

  describe "#judge_reasoning" do
    let(:batch_run) { FB.create(:raif_prompt_studio_batch_run, :with_judge_binary) }
    let(:source_task) { FB.create(:raif_test_task, :completed, creator: creator) }
    let(:item) { batch_run.items.create!(source_task: source_task) }

    it "returns nil when no judge_task" do
      expect(item.judge_reasoning).to be_nil
    end

    it "returns the reasoning from the judge response" do
      judge = FB.create(
        :raif_test_task,
        :completed,
        creator: creator,
        response_format: :json,
        raw_response: '{"passes": true, "reasoning": "The response is thorough and accurate", "confidence": 0.9}',
        type: "Raif::Evals::LlmJudges::Binary"
      )
      item.update!(judge_task: judge)

      expect(item.judge_reasoning).to eq("The response is thorough and accurate")
    end
  end
end
