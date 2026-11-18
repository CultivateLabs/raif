# frozen_string_literal: true

# One turn of an agent run: one model completion and the tool calls it asked for.
#
# The status is the durable record of how far the turn got. Every job that works
# on a turn reads the status first, so a job that runs a second time continues
# from the saved state instead of repeating a model call or a tool call.
#
#   pending           the model completion is not saved yet
#   completion_saved  the completion is saved; its tool calls are not dispatched
#   tools_dispatched  invocation rows exist; the agent is waiting for them
#   tools_complete    every invocation is terminal and the results are in the
#                     conversation history; the continuation has not run yet
#   completed         the next turn exists, or the run is over
class Raif::AgentTurn < Raif::ApplicationRecord
  include Raif::Concerns::ToolBarrier

  STATUSES = ["pending", "completion_saved", "tools_dispatched", "tools_complete", "completed"].freeze

  belongs_to :raif_agent, class_name: "Raif::Agent", inverse_of: :turns
  belongs_to :raif_model_completion, class_name: "Raif::ModelCompletion", optional: true

  has_many :raif_model_tool_invocations,
    class_name: "Raif::ModelToolInvocation",
    foreign_key: :raif_agent_turn_id,
    inverse_of: :raif_agent_turn,
    dependent: :nullify

  validates :status, inclusion: { in: STATUSES }
  validates :iteration, presence: true, numericality: { greater_than: 0 }

  scope :unfinished, -> { where.not(status: "completed") }

  STATUSES.each do |status_name|
    define_method("#{status_name}?") { status == status_name }
  end

  # The agent instance that is driving this turn. Association targets are
  # dropped on reload, and the driving instance holds state that a second
  # instance of the same row would not have (the run token it was queued with,
  # the block given to #run!), so the binding is kept outside the association.
  def bind_agent(agent)
    @bound_agent = agent
    self
  end

  def raif_agent
    @bound_agent || super
  end

  # Compare-and-set on the status. Returns false when the turn is no longer in
  # `from`, which means another job already made this transition.
  def transition!(from:, to:, **attributes)
    now = Time.current
    updated = self.class.where(id: id, status: from).update_all(attributes.merge(status: to, updated_at: now))
    reload
    updated == 1
  end

  # --- Raif::Concerns::ToolBarrier ---

  def barrier_lock(&block)
    raif_agent.run_transaction(&block)
  end

  def awaiting_tool_results?
    reload.tools_dispatched?
  end

  def barrier_owner_live?
    raif_agent.run_live?
  end

  def barrier_tool_invocations
    raif_model_tool_invocations
  end

  def close_tool_barrier!
    raif_agent.record_turn_tool_results!(self)
    transition!(from: "tools_dispatched", to: "tools_complete", tools_completed_at: Time.current)
  end

  def continue_after_tools!
    raif_agent.with_run_context { raif_agent.continue_after_turn!(self) }
  end

  def with_tool_run_context(&block)
    raif_agent.with_run_context(&block)
  end

  # Whether an exception raised by a tool becomes an error result for the model
  # (true) or ends the run (false).
  def recoverable_tool_error?(error)
    raif_agent.tool_error_recoverable?(error)
  end

  def tool_error_message_for_model(invocation, error)
    raif_agent.tool_error_message_for_model(invocation.tool_name, error)
  end

  def report_tool_error(invocation, error)
    Rails.error.report(error, handled: true, severity: :error, context: {
      component: "raif_agent",
      action: "invoke_tool",
      agent_id: raif_agent_id,
      tool_name: invocation.tool_name
    })
  end

  def fail_from_tool_error!(invocation, error)
    raif_agent.fail_run_from_tool_error!(invocation, error)
  end
end
