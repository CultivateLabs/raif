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

  def renderable?
    false
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

class Raif::DurableRunRetrySafeDeferredTestTool < Raif::ModelTool
  extend Raif::DurableRunTestRecorder

  retry_safe lease: 2.minutes
  defers_completion deadline: 45.minutes
end

class Raif::DurableRunTestAgent < Raif::Agents::NativeToolCallingAgent
  class << self
    def events
      @events ||= []
    end

    # The host context seen by each after_conversation_history_entry call.
    def history_contexts
      @history_contexts ||= []
    end

    # The host context seen by each after_run call.
    def run_contexts
      @run_contexts ||= []
    end

    def reset!
      @events = []
      @history_contexts = []
      @run_contexts = []
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
    self.class.history_contexts << Thread.current[:raif_durable_run_context]
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
    self.class.run_contexts << Thread.current[:raif_durable_run_context]
  end
end

# Adds a deferred tool only through populate_default_model_tools, which runs when
# the record is created.
class Raif::DurableRunDefaultDeferredToolAgent < Raif::DurableRunTestAgent
private

  def populate_default_model_tools
    self.available_model_tools = [Raif::DurableRunTestTool, Raif::DurableRunDeferredTestTool]
  end
end

# Subclasses Raif::Agent directly and processes each completion in the hook,
# recording how many transactions are open while the hook runs.
class Raif::DurableRunHookAgent < Raif::Agent
  class << self
    def open_transactions_in_hook
      @open_transactions_in_hook ||= []
    end

    def open_transactions_in_history_callback
      @open_transactions_in_history_callback ||= []
    end

    # How many more hook runs raise after adding their entry.
    attr_accessor :hook_failures_left

    def reset!
      @open_transactions_in_hook = []
      @open_transactions_in_history_callback = []
      @hook_failures_left = 0
    end
  end

  def after_conversation_history_entry(entry)
    self.class.open_transactions_in_history_callback << self.class.connection.open_transactions
    super
  end

private

  def build_system_prompt
    "You are a test agent."
  end

  def process_iteration_model_completion(model_completion)
    self.class.open_transactions_in_hook << self.class.connection.open_transactions
    add_conversation_history_entry({ "role" => "assistant", "content" => model_completion.raw_response })
    self.final_answer = model_completion.raw_response

    if self.class.hook_failures_left.to_i > 0
      self.class.hook_failures_left -= 1
      raise "The hook stopped after adding its entry"
    end
  end
end

class Raif::DurableRunTestConversation < Raif::Conversation
  class << self
    def finalized_entry_ids
      @finalized_entry_ids ||= []
    end

    # The host context seen by each on_entry_finalized call.
    def finalized_contexts
      @finalized_contexts ||= []
    end

    def reset!
      @finalized_entry_ids = []
      @finalized_contexts = []
    end
  end

  before_create do
    self.available_model_tools = [
      "Raif::DurableRunTestTool",
      "Raif::DurableRunSecondTestTool",
      "Raif::DurableRunDeferredTestTool",
    ]
  end

  def with_run_context(entry:)
    Thread.current[:raif_durable_run_context] = "entry-#{entry.id}"
    yield
  ensure
    Thread.current[:raif_durable_run_context] = nil
  end

  def on_entry_finalized(entry:)
    self.class.finalized_entry_ids << entry.id
    self.class.finalized_contexts << Thread.current[:raif_durable_run_context]
  end
end

Raif.config.agent_types += ["Raif::DurableRunTestAgent", "Raif::DurableRunDefaultDeferredToolAgent", "Raif::DurableRunHookAgent"]
Raif.config.conversation_types += ["Raif::DurableRunTestConversation"]

RSpec.configure do |config|
  config.before do
    [
      Raif::DurableRunTestTool,
      Raif::DurableRunSecondTestTool,
      Raif::DurableRunRetrySafeTestTool,
      Raif::DurableRunDeferredTestTool,
      Raif::DurableRunRetrySafeDeferredTestTool,
      Raif::DurableRunTestAgent,
      Raif::DurableRunHookAgent,
      Raif::DurableRunTestConversation
    ].each(&:reset!)
  end
end
