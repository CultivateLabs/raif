# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_tasks
#
#  id                     :bigint           not null, primary key
#  available_model_tools  :jsonb            not null
#  completed_at           :datetime
#  creator_type           :string
#  failed_at              :datetime
#  llm_model_key          :string           not null
#  prompt                 :text
#  prompt_studio_run      :boolean          default(FALSE), not null
#  raw_response           :text
#  requested_language_key :string
#  response_format        :integer          default("text"), not null
#  run_with               :jsonb
#  source_type            :string
#  started_at             :datetime
#  system_prompt          :text
#  type                   :string           not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  creator_id             :bigint
#  source_id              :bigint
#
# Indexes
#
#  index_raif_tasks_on_completed_at           (completed_at)
#  index_raif_tasks_on_created_at             (created_at)
#  index_raif_tasks_on_creator                (creator_type,creator_id)
#  index_raif_tasks_on_failed_at              (failed_at)
#  index_raif_tasks_on_source                 (source_type,source_id)
#  index_raif_tasks_on_started_at             (started_at)
#  index_raif_tasks_on_type                   (type)
#  index_raif_tasks_on_type_and_completed_at  (type,completed_at)
#  index_raif_tasks_on_type_and_failed_at     (type,failed_at)
#  index_raif_tasks_on_type_and_started_at    (type,started_at)
#
require "rails_helper"

RSpec.describe Raif::Evals::LlmJudge do
  describe "class configuration" do
    it "sets temperature to 0.0 for consistent judging" do
      judge = described_class.new
      expect(judge.temperature).to eq(0.0)
    end

    it "uses JSON response format" do
      judge = described_class.new
      expect(judge.response_format).to eq("json")
    end
  end

  describe "#default_llm_model_key" do
    let(:judge) { described_class.new }

    context "when evals_default_llm_judge_model_key is configured" do
      before do
        allow(Raif.config).to receive(:evals_default_llm_judge_model_key).and_return(:claude_3_5_sonnet)
      end

      it "uses the configured judge model key" do
        expect(judge.default_llm_model_key).to eq(:claude_3_5_sonnet)
      end
    end

    context "when evals_default_llm_judge_model_key is not configured" do
      before do
        allow(Raif.config).to receive(:evals_default_llm_judge_model_key).and_return(nil)
      end

      it "falls back to the default task model key" do
        expect(judge.default_llm_model_key).to eq(:raif_test_llm)
      end
    end
  end

  describe "#judgment_reasoning" do
    let(:judge) { described_class.new }

    context "when completed" do
      before do
        allow(judge).to receive(:completed?).and_return(true)
        allow(judge).to receive(:parsed_response).and_return({ "reasoning" => "The output is well-structured" })
      end

      it "returns the reasoning from parsed response" do
        expect(judge.judgment_reasoning).to eq("The output is well-structured")
      end
    end

    context "when not completed" do
      before do
        allow(judge).to receive(:completed?).and_return(false)
      end

      it "returns nil" do
        expect(judge.judgment_reasoning).to be_nil
      end
    end
  end

  describe "#judgment_confidence" do
    let(:judge) { described_class.new }

    context "when completed" do
      before do
        allow(judge).to receive(:completed?).and_return(true)
        allow(judge).to receive(:parsed_response).and_return({ "confidence" => 0.85 })
      end

      it "returns the confidence from parsed response" do
        expect(judge.judgment_confidence).to eq(0.85)
      end
    end

    context "when not completed" do
      before do
        allow(judge).to receive(:completed?).and_return(false)
      end

      it "returns nil" do
        expect(judge.judgment_confidence).to be_nil
      end
    end
  end

  describe "#low_confidence?" do
    let(:judge) { described_class.new }

    context "when confidence is below 0.5" do
      before do
        allow(judge).to receive(:judgment_confidence).and_return(0.3)
      end

      it "returns true" do
        expect(judge.low_confidence?).to be true
      end
    end

    context "when confidence is 0.5 or above" do
      before do
        allow(judge).to receive(:judgment_confidence).and_return(0.7)
      end

      it "returns false" do
        expect(judge.low_confidence?).to be false
      end
    end

    context "when confidence is nil" do
      before do
        allow(judge).to receive(:judgment_confidence).and_return(nil)
      end

      it "returns falsey" do
        expect(judge.low_confidence?).to be_falsey
      end
    end
  end
end
