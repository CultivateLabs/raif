# frozen_string_literal: true

# Tools and an agent class for the durable-run specs. Each tool records its
# executions on the class, so a spec can assert how many times a tool ran.
module Raif::DurableRunTestRecorder
  # Tool definitions are per class, so each test tool declares its own.
  def self.extended(tool)
    tool.tool_arguments_schema { string :query }
    tool.example_model_invocation { { "name" => tool.tool_name, "arguments" => { "query" => "example" } } }
    tool.tool_description { "Looks something up" }
  end

  def executions
    @executions ||= []
  end

  def reset!
    @executions = []
    @behavior = nil
  end

  # A block run inside process_invocation, to raise or to observe context.
  def behavior(&block)
    @behavior = block if block_given?
    @behavior
  end

  def process_invocation(invocation)
    executions << invocation.id
    behavior&.call(invocation)
    return if deferred_completion?

    invocation.update!(result: { "answer" => "result for #{invocation.tool_arguments["query"]}" })
  end
end

class Raif::DurableRunTestTool < Raif::ModelTool
  extend Raif::DurableRunTestRecorder
end

class Raif::DurableRunSecondTestTool < Raif::ModelTool
  extend Raif::DurableRunTestRecorder
end

class Raif::DurableRunRetrySafeTestTool < Raif::ModelTool
  extend Raif::DurableRunTestRecorder

  retry_safe lease: 2.minutes
end

class Raif::DurableRunDeferredTestTool < Raif::ModelTool
  extend Raif::DurableRunTestRecorder

  defers_completion deadline: 45.minutes
end

class Raif::DurableRunTestAgent < Raif::Agents::NativeToolCallingAgent
  class << self
    def events
      @events ||= []
    end

    def reset!
      @events = []
    end
  end

  def with_run_context
    Thread.current[:raif_durable_run_context] = "agent-#{id}"
    yield
  ensure
    Thread.current[:raif_durable_run_context] = nil
  end

  def after_conversation_history_entry(entry)
    self.class.events << [:entry, entry["type"] || entry["role"]]
    super
  end

  def after_tool_calls_dispatched(turn)
    self.class.events << [:dispatched, turn.iteration]
  end

  def after_turn(turn)
    self.class.events << [:turn, turn.iteration]
  end

  def after_run
    self.class.events << [:run, status]
  end
end

Raif.config.agent_types += ["Raif::DurableRunTestAgent"]

RSpec.configure do |config|
  config.before do
    [
      Raif::DurableRunTestTool,
      Raif::DurableRunSecondTestTool,
      Raif::DurableRunRetrySafeTestTool,
      Raif::DurableRunDeferredTestTool,
      Raif::DurableRunTestAgent
    ].each(&:reset!)
  end
end
