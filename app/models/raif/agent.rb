# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_agents
#
#  id                     :bigint           not null, primary key
#  available_model_tools  :jsonb            not null
#  canceled_at            :datetime
#  completed_at           :datetime
#  conversation_history   :jsonb            not null
#  creator_type           :string           not null
#  failed_at              :datetime
#  failure_reason         :text
#  final_answer           :text
#  iteration_count        :integer          default(0), not null
#  llm_model_key          :string           not null
#  max_iterations         :integer          default(10), not null
#  requested_language_key :string
#  run_mode               :string
#  run_token              :string
#  run_with               :jsonb
#  source_type            :string
#  started_at             :datetime
#  system_prompt          :text
#  task                   :text
#  type                   :string           not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  creator_id             :bigint           not null
#  source_id              :bigint
#
# Indexes
#
#  index_raif_agents_on_created_at  (created_at)
#  index_raif_agents_on_creator     (creator_type,creator_id)
#  index_raif_agents_on_source      (source_type,source_id)
#
module Raif
  class Agent < ApplicationRecord
    prepend Raif::Concerns::HasPromptTemplates

    include Raif::Concerns::HasLlm
    include Raif::Concerns::HasRequestedLanguage
    include Raif::Concerns::HasAvailableModelTools
    include Raif::Concerns::HasRuntimeDuration
    include Raif::Concerns::InvokesModelTools
    include Raif::Concerns::AgentInferenceStats
    include Raif::Concerns::LlmPromptCaching
    include Raif::Concerns::LlmDataRetention
    include Raif::Concerns::RunWith
    include Raif::Concerns::DurableAgentRun

    # Whether the agent may make multiple tool calls in a single iteration. When
    # false, a completion containing more than one tool call is rejected and the
    # model is asked to call one tool at a time (the historical behavior).
    class_attribute :parallel_tool_calls, instance_writer: false, default: true

    # Optional cap on the number of tool calls accepted in a single iteration.
    # nil means uncapped. A batch exceeding the cap is rejected with corrective
    # feedback rather than partially invoked.
    class_attribute :max_tool_calls_per_iteration, instance_writer: false, default: nil

    # When true, an exception raised by a tool does not fail the run. The agent
    # reports it through Rails.error, marks the invocation failed, and sends the
    # model an error as that call's result so it can try another approach. Override
    # #recoverable_tool_error? to let other errors fail the run. A model_completion_authorizer
    # veto fails the run by default.
    class_attribute :recover_from_tool_errors, instance_writer: false, default: true

    belongs_to :creator, polymorphic: true
    belongs_to :source, polymorphic: true, optional: true

    has_many :raif_model_completions, as: :source, dependent: :destroy, class_name: "Raif::ModelCompletion"

    after_initialize -> { self.available_model_tools ||= [] }
    after_initialize -> { self.conversation_history ||= [] }
    after_initialize -> { self.run_with ||= {} }

    boolean_timestamp :started_at
    boolean_timestamp :completed_at
    boolean_timestamp :failed_at

    validates :type, inclusion: { in: ->{ Raif.config.agent_types } }
    validates :task, presence: true
    validates :system_prompt, presence: true
    validates :max_iterations, presence: true, numericality: { greater_than: 0 }

    before_validation -> {
      populate_default_model_tools
      self.system_prompt ||= build_system_prompt
    },
      on: :create

    attr_accessor :on_conversation_history_entry

    def final_iteration?
      iteration_count == max_iterations
    end

    # Per-tool invocation counts for the admin agent show page, keyed by tool
    # class name (e.g. "Raif::ModelTools::ProviderManaged::WebSearch") so the
    # `_list` partial can look up `counts[tool_class.name]`.
    #
    # Combines two sources:
    # - Developer-managed tools persist as Raif::ModelToolInvocation rows via
    #   Raif::ModelTool.invoke_tool.
    # - Provider-managed tools (e.g. Anthropic / OpenAI web_search) never reach
    #   that path - they live as `server_tool_use` / `web_search_call` blocks
    #   in each completion's `response_array` and are surfaced via
    #   ModelCompletion#provider_managed_tool_calls.
    def model_tool_invocation_counts
      counts = raif_model_tool_invocations.group(:tool_type).count

      raif_model_completions.find_each do |completion|
        Array(completion.provider_managed_tool_calls).each do |call|
          tool_klass = completion.available_model_tools_map[call["tool_name"]]
          next unless tool_klass

          counts[tool_klass.name] = (counts[tool_klass.name] || 0) + 1
        end
      end

      counts
    end

  private

    def populate_default_model_tools
      # no-op by default. Can be overridden by subclasses to add default model tools
    end

    def finalize_run!
      validate_successful_completion
      return if failed?

      completed!
    end

    def validate_successful_completion
      # no-op by default. Can be overridden by subclasses to enforce success criteria.
    end

    def process_iteration_model_completion(model_completion)
      raise NotImplementedError, "#{self.class.name} must implement process_iteration_model_completion"
    end

    def native_model_tools
      # no-op by default
    end

    # Hook for subclasses to perform actions before the LLM chat on each iteration
    # Override in subclasses to add warnings, context, etc.
    def before_iteration_llm_chat
      # no-op by default
    end

    # Hook for subclasses to specify tool_choice for the current iteration
    # Override in subclasses to force specific tools (e.g., on final iteration)
    # @return [Class, nil] A model tool class (e.g., Raif::ModelTools::AgentFinalAnswer), or nil for default behavior
    def tool_choice_for_iteration
      nil
    end

    # Hook for subclasses: whether the current iteration's request should permit
    # the provider to return multiple tool calls. Returns false here in the base
    # class. Raif::Agents::NativeToolCallingAgent overrides this and permits
    # parallel calls by default, controlled by its parallel_tool_calls class
    # attribute (default true) and Raif::Llm#supports_parallel_tool_calls?.
    # @return [Boolean]
    def allow_parallel_tool_calls?
      false
    end

    # Hook for subclasses to require a specific tool on the current iteration.
    # Override to align prompt warnings and provider-level tool_choice.
    # Overrides should be deterministic and side-effect free for a given iteration.
    # @return [Class, nil] A model tool class, or nil if no specific tool is required.
    def required_tool_for_iteration
      nil
    end

    # The messages sent to the provider for this iteration. Defaults to the
    # persisted conversation history. Subclasses override it when an entry's
    # model-facing content must be re-derived on every turn rather than read
    # back from storage.
    #
    # @return [Array<Hash>] Message hashes in provider-agnostic form.
    def messages_for_llm
      conversation_history
    end

    def add_conversation_history_entry(entry)
      # Tool results carry arbitrary external content (fetched pages, search
      # results) that can contain NUL bytes, which Postgres cannot store in a
      # jsonb column. Strip them before persisting so a single poisoned tool
      # result doesn't abort the whole agent run.
      entry_stringified = strip_null_bytes(entry.stringify_keys)
      if @buffered_history_entries
        @buffered_history_entries << entry_stringified
        return
      end

      conversation_history << entry_stringified
      save!

      # Inside #run_transaction the callback waits for the block to return, so
      # host code does not run while Raif holds the agent's row lock. A host
      # transaction around #complete! or #fail! keeps the lock until it commits.
      (@conversation_history_callback_queue ||= []) << entry_stringified
      flush_conversation_history_callbacks unless @run_transaction_depth.to_i > 0
    end

    def strip_null_bytes(value)
      case value
      when String
        value.delete("\u0000")
      when Hash
        value.transform_values { |v| strip_null_bytes(v) }
      when Array
        value.map { |v| strip_null_bytes(v) }
      else
        value
      end
    end

    def fail_run!(reason)
      self.failed_at ||= Time.current
      self.failure_reason ||= reason
      save!
    end

    def build_system_prompt
      raise NotImplementedError, "Subclasses of Raif::Agent must implement build_system_prompt"
    end

  end
end
