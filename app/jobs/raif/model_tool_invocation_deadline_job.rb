# frozen_string_literal: true

module Raif
  # Ends a tool invocation that is still unfinished at its deadline, so the agent
  # or conversation waiting for it continues with an error result for that call.
  # Queued with a delay when the invocation is dispatched.
  # Raif::RecoverStalledRunsJob covers the case where this job is lost.
  class ModelToolInvocationDeadlineJob < ApplicationJob

    def perform(model_tool_invocation:)
      invocation = model_tool_invocation
      return if invocation.finished? || invocation.deadline_at.blank?

      # The deadline was extended after this job was queued.
      return if invocation.deadline_at > Time.current

      invocation.expire!
    end

  end
end
