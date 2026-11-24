# frozen_string_literal: true

module Raif
  # Runs one tool call of an agent turn or a conversation entry. The calls of a
  # turn each get a job, so they run in parallel across workers.
  #
  # The invocation's claim decides whether this job runs the tool: a duplicate
  # delivery, or a job for a run that already ended, does nothing.
  class ModelToolInvocationJob < ApplicationJob

    queue_as { Raif.config.model_tool_invocation_job_queue || :default }

    def perform(model_tool_invocation:)
      invocation = model_tool_invocation
      return if invocation.finished?

      ran = invocation.execute!
      return if ran || invocation.reload.finished?

      # Another execution holds the claim. For a tool that declared `retry_safe`,
      # come back when its lease has expired and take the invocation over if it
      # is still unfinished.
      if invocation.tool.retry_safe? && invocation.lease_expires_at.present?
        self.class.set(queue: queue_name, wait_until: invocation.lease_expires_at + 1.second)
          .perform_later(model_tool_invocation: invocation)
      end
    end

  end
end
