# frozen_string_literal: true

# The barrier that holds an agent turn or a conversation entry until every tool
# call it dispatched is terminal.
#
# Tool calls of one turn run as separate jobs and can end in any order, and a
# deferred call ends only when the host says so. Every path that makes an
# invocation terminal (the tool returning, #complete!, #fail!, a deadline) calls
# #check_tool_barrier! on the owner. The check runs under a row lock, so when two
# invocations end at the same moment exactly one caller sees "none left" and
# opens the barrier.
#
# Opening the barrier and continuing are two steps on purpose. The barrier commit
# is the durable record that the continuation is owed. If the process stops
# between the two, recovery (Raif::RecoverStalledRunsJob, Raif::Agent#resume!)
# finds the owner in its "tools complete" state and runs the continuation.
#
# An including class implements:
#   barrier_lock(&block)        run the block in a transaction holding the owner's lock
#   awaiting_tool_results?      true while tool calls are dispatched and the barrier is closed
#   barrier_owner_live?         false once the owner failed, was canceled, or was superseded
#   barrier_tool_invocations    relation of the invocations behind this barrier
#   close_tool_barrier!         record the results in call order and mark "tools complete"
#   continue_after_tools!       repeatable; does nothing unless the owner is "tools complete"
#   with_tool_run_context       restore host context around tool code and the barrier; reentrant
#   recoverable_tool_error?     whether a tool exception becomes an error result
#   tool_error_message_for_model, fail_from_tool_error!
module Raif::Concerns::ToolBarrier
  extend ActiveSupport::Concern

  # Reads the latest committed rows of the relation inside the barrier.
  #
  # Postgres at READ COMMITTED gives every statement a fresh snapshot, so a
  # plain read is enough. MySQL at REPEATABLE READ reads the transaction's
  # snapshot, which can predate the commit of the caller that finished the
  # previous call, so it needs a locking read. A locking read there waits on any
  # invocation row the host locked in its own transaction, and that host then
  # waits for the owner's lock: on MySQL, host code must not write or lock an
  # invocation before it calls #complete! or #fail! in the same transaction.
  def self.current_rows(relation)
    relation.connection.adapter_name.downcase.in?(["mysql2", "trilogy"]) ? relation.lock : relation
  end

  # Runs inside the owner's host context, because opening the barrier runs host
  # hooks (the agent's conversation history callbacks, the continuation).
  #
  # @return [Boolean] true when this call opened the barrier
  def check_tool_barrier!
    with_tool_run_context { check_tool_barrier_in_context! }
  end

private

  def check_tool_barrier_in_context!
    opened = barrier_lock do
      next false unless awaiting_tool_results? && barrier_owner_live?
      next false if Raif::Concerns::ToolBarrier.current_rows(barrier_tool_invocations.unfinished).exists?

      close_tool_barrier!
      true
    end

    continue_after_tools! if opened
    opened
  end
end
