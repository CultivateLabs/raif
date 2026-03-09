# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_prompt_studio_batch_run_items
#
#  id             :bigint           not null, primary key
#  metadata       :jsonb
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

module Raif
  class PromptStudioBatchRunItem < Raif::ApplicationRecord
    include ActionView::RecordIdentifier

    STATUSES = %w[pending running judging completed failed].freeze

    after_initialize -> { self.metadata ||= {} }

    belongs_to :batch_run,
      class_name: "Raif::PromptStudioBatchRun",
      inverse_of: :items

    belongs_to :source_task,
      class_name: "Raif::Task"

    belongs_to :result_task,
      class_name: "Raif::Task",
      optional: true

    belongs_to :judge_task,
      class_name: "Raif::Task",
      optional: true

    validates :status, inclusion: { in: STATUSES }

    def execute!
      update!(status: "running")
      broadcast_item

      new_task = create_and_run_task
      run_judge_if_configured(new_task)

      update!(status: "completed")
    rescue StandardError => e
      Rails.logger.error "Error running batch run item ##{id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      update!(status: "failed")
    ensure
      broadcast_item
      batch_run.check_completion!
      broadcast_progress
    end

    def judge_summary
      return unless judge_task&.completed?

      parsed = judge_task.parsed_response
      return unless parsed.is_a?(Hash)

      case batch_run.judge_type
      when "Raif::Evals::LlmJudges::Binary"
        parsed["passes"] ? "PASS" : "FAIL"
      when "Raif::Evals::LlmJudges::Scored"
        "Score: #{parsed["score"]}"
      when "Raif::Evals::LlmJudges::Comparative"
        if parsed["winner"] == "tie"
          I18n.t("raif.admin.prompt_studio.batch_runs.judge.tie")
        else
          winner_label = comparative_winner_label(parsed["winner"])
          I18n.t("raif.admin.prompt_studio.batch_runs.judge.winner", name: winner_label)
        end
      when "Raif::Evals::LlmJudges::Summarization"
        "Overall: #{parsed.dig("overall", "score")}/5"
      end
    end

    def judge_reasoning
      return unless judge_task&.completed?

      parsed = judge_task.parsed_response
      return unless parsed.is_a?(Hash)

      parsed["reasoning"]
    end

    def comparative_winner_label(winner_letter)
      new_response_letter = metadata&.dig("new_response_letter")
      return winner_letter unless new_response_letter

      if winner_letter == new_response_letter
        I18n.t("raif.admin.prompt_studio.batch_runs.judge.new_response")
      else
        I18n.t("raif.admin.prompt_studio.batch_runs.judge.original_response")
      end
    end

  private

    def create_and_run_task
      new_task = source_task.class.new(
        creator: source_task.creator,
        source: source_task,
        llm_model_key: batch_run.llm_model_key,
        available_model_tools: source_task.available_model_tools,
        run_with: source_task.run_with,
        prompt_studio_run: true,
        started_at: Time.current
      )
      new_task.assign_attributes(source_task.prompt_studio_rerun_attributes)
      apply_prompt_studio_task_attributes(new_task)
      new_task.save!

      update!(result_task_id: new_task.id)
      new_task.run
      new_task
    end

    def run_judge_if_configured(new_task)
      return unless batch_run.has_judge? && new_task.completed?

      update!(status: "judging")
      broadcast_item

      judge_result = invoke_judge(new_task)
      update!(judge_task_id: judge_result.id)
    end

    def invoke_judge(new_task)
      judge_class = batch_run.judge_class
      config = batch_run.judge_config
      judge_args = {
        creator: source_task.creator,
        prompt_studio_run: true,
        llm_model_key: batch_run.judge_llm_model_key
      }
      judge_args.merge!(prompt_studio_task_attributes)

      if config["include_original_prompt_as_context"]
        judge_args[:additional_context] =
          "The content being evaluated was generated in response to the following prompt:\n\n#{source_task.prompt}"
      end

      case batch_run.judge_type
      when "Raif::Evals::LlmJudges::Binary"
        judge_class.run(
          content_to_judge: new_task.raw_response,
          criteria: config["criteria"],
          strict_mode: config["strict_mode"],
          **judge_args
        )
      when "Raif::Evals::LlmJudges::Scored"
        rubric = Raif::Evals::ScoringRubric.send(config["scoring_rubric"])
        judge_class.run(
          content_to_judge: new_task.raw_response,
          scoring_rubric: rubric,
          **judge_args
        )
      when "Raif::Evals::LlmJudges::Comparative"
        result = judge_class.run(
          content_to_judge: new_task.raw_response,
          over_content: source_task.raw_response,
          comparison_criteria: config["comparison_criteria"],
          **judge_args
        )
        # Store which letter was assigned to the new response so we can display
        # "Winner: New Response" / "Winner: Original Response" instead of "A"/"B"
        update!(metadata: metadata.merge("new_response_letter" => result.expected_winner))
        result
      when "Raif::Evals::LlmJudges::Summarization"
        judge_class.run(
          original_content: source_task.prompt,
          summary: new_task.raw_response,
          **judge_args
        )
      end
    end

    def broadcast_item
      Turbo::StreamsChannel.broadcast_replace_to(
        batch_run,
        target: dom_id(self),
        partial: "raif/admin/prompt_studio/batch_runs/batch_run_item",
        locals: { item: self }
      )
    end

    def broadcast_progress
      batch_run.reload
      Turbo::StreamsChannel.broadcast_replace_to(
        batch_run,
        target: dom_id(batch_run, :progress),
        partial: "raif/admin/prompt_studio/batch_runs/progress",
        locals: { batch_run: batch_run }
      )
    end

    def prompt_studio_task_attributes
      callback = Raif.config.prompt_studio_task_attributes
      return {} unless callback

      callback.call(source_task)
    end

    def apply_prompt_studio_task_attributes(task)
      attrs = prompt_studio_task_attributes
      task.assign_attributes(attrs) if attrs.present?
    end
  end
end
