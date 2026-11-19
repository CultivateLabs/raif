# frozen_string_literal: true

module Raif
  # Performs one step of an agent run that was started with Raif::Agent#run_later!.
  #
  # The job reads the turn's saved state and does what is still missing: request
  # the model completion, dispatch its tool calls, or continue to the next turn.
  # It ends as soon as the turn waits for tool calls, so no job holds a worker
  # for a whole run. Running it again for the same turn is harmless.
  class AgentTurnJob < ApplicationJob

    queue_as { Raif.config.agent_turn_job_queue || :default }

    # @param agent [Raif::Agent]
    # @param turn_id [Integer]
    # @param run_token [String] the agent's run token when the job was queued. A
    #   job whose token no longer matches belongs to a canceled or superseded run.
    def perform(agent:, turn_id:, run_token:)
      return if agent.run_over? || agent.run_token != run_token

      turn = agent.turns.find_by(id: turn_id)
      return if turn.nil? || turn.completed?

      agent.hold_run_token(run_token)
      agent.perform_turn!(turn)
    rescue StandardError => e
      # Same outcome as an error raised out of Raif::Agent#run!: the run fails.
      # Transient provider errors were already retried inside Raif::Llm#chat.
      Rails.error.report(e, handled: true, severity: :error, context: {
        component: "raif_agent_turn_job",
        agent_id: agent.id
      })
      agent.fail_run_from_turn_error!(e)
    end

  end
end
