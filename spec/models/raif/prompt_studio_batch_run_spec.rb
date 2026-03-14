# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_prompt_studio_batch_runs
#
#  id                  :bigint           not null, primary key
#  completed_at        :datetime
#  completed_count     :integer          default(0), not null
#  failed_at           :datetime
#  failed_count        :integer          default(0), not null
#  judge_config        :jsonb            not null
#  judge_llm_model_key :string
#  judge_type          :string
#  llm_model_key       :string           not null
#  started_at          :datetime
#  task_type           :string           not null
#  total_count         :integer          default(0), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
require "rails_helper"

RSpec.describe Raif::PromptStudioBatchRun, type: :model do
  describe "validations" do
    it "requires task_type" do
      batch_run = FB.build(:raif_prompt_studio_batch_run, task_type: nil)
      expect(batch_run).not_to be_valid
      expect(batch_run.errors[:task_type]).to be_present
    end

    it "requires llm_model_key" do
      batch_run = FB.build(:raif_prompt_studio_batch_run, llm_model_key: nil)
      expect(batch_run).not_to be_valid
      expect(batch_run.errors[:llm_model_key]).to be_present
    end

    it "allows nil judge_type" do
      batch_run = FB.build(:raif_prompt_studio_batch_run, judge_type: nil)
      expect(batch_run).to be_valid
    end

    it "validates judge_type inclusion" do
      batch_run = FB.build(:raif_prompt_studio_batch_run, judge_type: "InvalidJudge")
      expect(batch_run).not_to be_valid
      expect(batch_run.errors[:judge_type]).to be_present
    end

    it "accepts valid judge types" do
      Raif::PromptStudioBatchRun::ALLOWED_JUDGE_TYPES.each do |jt|
        batch_run = FB.build(:raif_prompt_studio_batch_run, judge_type: jt)
        expect(batch_run).to be_valid
      end
    end
  end

  describe "#status" do
    it "returns :pending when no timestamps set" do
      batch_run = FB.build(:raif_prompt_studio_batch_run)
      expect(batch_run.status).to eq(:pending)
    end

    it "returns :in_progress when started" do
      batch_run = FB.build(:raif_prompt_studio_batch_run, started_at: Time.current)
      expect(batch_run.status).to eq(:in_progress)
    end

    it "returns :completed when completed" do
      batch_run = FB.build(:raif_prompt_studio_batch_run, :completed)
      expect(batch_run.status).to eq(:completed)
    end

    it "returns :failed when failed" do
      batch_run = FB.build(:raif_prompt_studio_batch_run, started_at: Time.current, failed_at: Time.current)
      expect(batch_run.status).to eq(:failed)
    end
  end

  describe "#progress_percentage" do
    it "returns 0 when total_count is zero" do
      batch_run = FB.build(:raif_prompt_studio_batch_run, total_count: 0)
      expect(batch_run.progress_percentage).to eq(0)
    end

    it "calculates percentage from completed and failed counts" do
      batch_run = FB.build(:raif_prompt_studio_batch_run, total_count: 10, completed_count: 7, failed_count: 1)
      expect(batch_run.progress_percentage).to eq(80)
    end

    it "returns 100 when all done" do
      batch_run = FB.build(:raif_prompt_studio_batch_run, total_count: 5, completed_count: 4, failed_count: 1)
      expect(batch_run.progress_percentage).to eq(100)
    end
  end

  describe "#has_judge?" do
    it "returns false when judge_type is nil" do
      batch_run = FB.build(:raif_prompt_studio_batch_run, judge_type: nil)
      expect(batch_run.has_judge?).to be false
    end

    it "returns true when judge_type is present" do
      batch_run = FB.build(:raif_prompt_studio_batch_run, :with_judge_binary)
      expect(batch_run.has_judge?).to be true
    end
  end

  describe "#judge_class" do
    it "returns nil when judge_type is nil" do
      batch_run = FB.build(:raif_prompt_studio_batch_run)
      expect(batch_run.judge_class).to be_nil
    end

    it "returns the constantized class" do
      batch_run = FB.build(:raif_prompt_studio_batch_run, :with_judge_binary)
      expect(batch_run.judge_class).to eq(Raif::Evals::LlmJudges::Binary)
    end
  end

  describe "#judge_pass_rate" do
    let(:batch_run) { FB.create(:raif_prompt_studio_batch_run, :with_judge_binary, :completed) }
    let(:creator) { FB.create(:raif_test_user) }

    it "returns nil when no items have judge tasks" do
      source_task = FB.create(:raif_test_task, :completed, creator: creator)
      batch_run.items.create!(source_task: source_task, status: "completed")
      expect(batch_run.judge_pass_rate).to be_nil
    end

    it "calculates the pass rate as a percentage" do
      2.times do |i|
        source_task = FB.create(:raif_test_task, :completed, creator: creator)
        judge = FB.create(
          :raif_test_task,
          :completed,
          creator: creator,
          response_format: :json,
          raw_response: { passes: i == 0, reasoning: "ok", confidence: 0.9 }.to_json,
          type: "Raif::Evals::LlmJudges::Binary"
        )
        batch_run.items.create!(source_task: source_task, judge_task: judge, status: "completed")
      end

      expect(batch_run.judge_pass_rate).to eq("50% (1/2)")
    end
  end

  describe "#judge_average_score" do
    let(:batch_run) { FB.create(:raif_prompt_studio_batch_run, :with_judge_scored, :completed) }
    let(:creator) { FB.create(:raif_test_user) }

    it "returns nil when no items have scored judge tasks" do
      source_task = FB.create(:raif_test_task, :completed, creator: creator)
      batch_run.items.create!(source_task: source_task, status: "completed")
      expect(batch_run.judge_average_score).to be_nil
    end

    it "calculates the average score across judged items" do
      [3, 5].each do |score|
        source_task = FB.create(:raif_test_task, :completed, creator: creator)
        judge = FB.create(
          :raif_test_task,
          :completed,
          creator: creator,
          response_format: :json,
          raw_response: { score: score, reasoning: "ok", confidence: 0.9 }.to_json,
          type: "Raif::Evals::LlmJudges::Scored"
        )
        batch_run.items.create!(source_task: source_task, judge_task: judge, status: "completed")
      end

      expect(batch_run.judge_average_score).to eq(4.0)
    end
  end

  describe "#check_completion!" do
    let(:creator) { FB.create(:raif_test_user) }
    let(:batch_run) { FB.create(:raif_prompt_studio_batch_run, total_count: 2) }

    before do
      2.times do
        source_task = FB.create(:raif_test_task, :completed, creator: creator)
        batch_run.items.create!(source_task: source_task, status: "completed")
      end
    end

    it "sets completed_at when all items are done" do
      batch_run.check_completion!
      expect(batch_run.reload.completed_at).to be_present
      expect(batch_run.completed_count).to eq(2)
    end

    it "does not complete when items are still pending" do
      batch_run.items.last.update!(status: "running")
      batch_run.check_completion!
      expect(batch_run.reload.completed_at).to be_nil
    end
  end
end
