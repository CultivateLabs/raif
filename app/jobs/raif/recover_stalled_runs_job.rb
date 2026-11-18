# frozen_string_literal: true

module Raif
  # Safety sweep for agent runs and conversation entries that use tool jobs.
  # Every step of a run is queued by the step before it, so a job the queue
  # backend loses (a restart, a crashed worker) would otherwise stop the run for
  # good. The sweep finds work that stopped and starts it again:
  #
  # - tool invocations past their deadline whose deadline job never ran
  # - async agent runs whose current turn has not changed for
  #   Raif.config.agent_stalled_turn_resume_after
  # - conversation entries whose tool calls all ended but whose continuation
  #   never ran, or whose tool jobs were never queued
  #
  # Every action it takes is safe to repeat. Schedule it every few minutes with
  # the recurring-job mechanism of the host's queue adapter.
  class RecoverStalledRunsJob < ApplicationJob

    def perform
      expire_overdue_invocations
      resume_stalled_agent_runs
      recover_conversation_entries
    end

  private

    def expire_overdue_invocations
      Raif::ModelToolInvocation.overdue.find_each do |invocation|
        guarded("expire invocation", invocation) { invocation.expire! }
      end
    end

    def resume_stalled_agent_runs
      threshold = Raif.config.agent_stalled_turn_resume_after
      return if threshold.blank?

      turns = Raif::AgentTurn.arel_table
      Raif::AgentTurn.unfinished.where(turns[:updated_at].lt(threshold.ago)).includes(:raif_agent).find_each do |turn|
        guarded("resume agent", turn) { turn.raif_agent.resume! }
      end
    end

    def recover_conversation_entries
      threshold = Raif.config.agent_stalled_turn_resume_after
      return if threshold.blank?

      entries = Raif::ConversationEntry.arel_table
      Raif::ConversationEntry
        .where.not(tools_dispatched_at: nil)
        .where(completed_at: nil, failed_at: nil)
        .where(entries[:updated_at].lt(threshold.ago))
        .find_each do |entry|
          guarded("recover conversation entry", entry) { entry.recover_tool_calls! }
        end
    end

    # Per-record rescue so one bad record does not block the rest of the sweep.
    def guarded(action, record)
      yield
    rescue StandardError => e
      Raif.logger.error("Raif::RecoverStalledRunsJob: failed to #{action} #{record.class.name}##{record.id}: #{e.class}: #{e.message}")
      Rails.error.report(e, handled: true, severity: :error,
        context: { component: "raif_recover_stalled_runs_job", record_type: record.class.name, record_id: record.id })
    end

  end
end
