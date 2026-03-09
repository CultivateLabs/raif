# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_prompt_studio_batch_runs
#
#  id                  :bigint           not null, primary key
#  completed_at        :datetime
#  completed_count     :integer          default(0)
#  failed_at           :datetime
#  failed_count        :integer          default(0)
#  judge_config        :jsonb            not null
#  judge_llm_model_key :string
#  judge_type          :string
#  llm_model_key       :string           not null
#  started_at          :datetime
#  task_type           :string           not null
#  total_count         :integer          default(0)
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#

module Raif
  class PromptStudioBatchRun < Raif::ApplicationRecord
    ALLOWED_JUDGE_TYPES = [
      "Raif::Evals::LlmJudges::Binary",
      "Raif::Evals::LlmJudges::Scored",
      "Raif::Evals::LlmJudges::Comparative",
      "Raif::Evals::LlmJudges::Summarization"
    ].freeze

    after_initialize -> { self.judge_config ||= {} }

    has_many :items,
      class_name: "Raif::PromptStudioBatchRunItem",
      foreign_key: :batch_run_id,
      dependent: :destroy,
      inverse_of: :batch_run

    boolean_timestamp :started_at
    boolean_timestamp :completed_at
    boolean_timestamp :failed_at

    validates :task_type, presence: true
    validates :llm_model_key, presence: true
    validates :judge_type, inclusion: { in: ALLOWED_JUDGE_TYPES }, allow_nil: true

    def status
      if completed_at?
        :completed
      elsif failed_at?
        :failed
      elsif started_at?
        :in_progress
      else
        :pending
      end
    end

    def progress_percentage
      return 0 if total_count.zero?

      ((completed_count + failed_count).to_f / total_count * 100).round
    end

    def has_judge?
      judge_type.present?
    end

    def judge_class
      judge_type&.safe_constantize
    end

    def judge_pass_rate
      judge_tasks = completed_judge_tasks
      return if judge_tasks.empty?

      pass_count = judge_tasks.count(&:passes?)
      percentage = ((pass_count.to_f / judge_tasks.size) * 100).round
      "#{percentage}% (#{pass_count}/#{judge_tasks.size})"
    end

    def judge_average_score
      scores = completed_judge_tasks.filter_map(&:judgment_score)
      return if scores.empty?

      (scores.sum.to_f / scores.size).round(1)
    end

  private

    def completed_judge_tasks
      Raif::Task.where(
        id: items.where.not(judge_task_id: nil).select(:judge_task_id)
      ).where.not(completed_at: nil)
    end

  public

    def check_completion!
      reload
      remaining = items.where(status: %w[pending running judging]).count
      self.completed_count = items.where(status: "completed").count
      self.failed_count = items.where(status: "failed").count

      if remaining.zero?
        self.completed_at = Time.current
      end

      save!
    end
  end
end
