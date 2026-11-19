# frozen_string_literal: true

class Raif::ModelTool
  include Raif::Concerns::JsonSchemaDefinition

  delegate :tool_name, :tool_description, :example_model_invocation, to: :class

  class << self
    # The description of the tool that will be provided to the model
    # when giving it a list of available tools.
    #
    # @param source [Object, nil] Optional caller context forwarded into any
    #   source-aware schema or example blocks.
    def description_for_llm(source: nil)
      <<~DESCRIPTION
        Name: #{tool_name}
        Description: #{tool_description}
        Arguments Schema:
        #{JSON.pretty_generate(tool_arguments_schema_for_source(source))}
        Example Usage:
        #{JSON.pretty_generate(example_model_invocation_for_source(source))}
      DESCRIPTION
    end

    # The name of the tool as it will be provided to the model & used in the model invocation.
    # Default for something like Raif::ModelTools::WikipediaSearch would be "wikipedia_search"
    def tool_name
      name.split("::").last.underscore
    end

    def tool_description(&block)
      if block_given?
        @tool_description = block.call
      elsif @tool_description.present?
        @tool_description
      else
        raise NotImplementedError, "#{name}#tool_description is not implemented"
      end
    end

    # Defines or retrieves the tool's example model invocation.
    #
    # Definition:
    #   - Arity-0 block: the block's return value is the example (evaluated lazily
    #     on first read, then cached).
    #   - Arity-1 block: receives the caller `source` on each read. Not cached,
    #     so the example can reflect per-run context.
    #
    # @param source [Object, nil] Passed into arity-1 example blocks; ignored by
    #   arity-0 blocks.
    def example_model_invocation(source: nil, &block)
      if block_given?
        @example_model_invocation_block = block
        @example_model_invocation = nil
      elsif @example_model_invocation_block.present?
        if @example_model_invocation_block.arity == 1
          @example_model_invocation_block.call(source)
        else
          @example_model_invocation ||= @example_model_invocation_block.call
        end
      else
        raise NotImplementedError, "#{name}#example_model_invocation is not implemented"
      end
    end

    def process_invocation(invocation)
      raise NotImplementedError, "#{name}#process_invocation is not implemented"
    end

    # Runs the tool for an invocation. Every tool execution goes through here,
    # whatever started it: a task, an agent turn, a conversation entry, a tool
    # job, a tool that defers completion, or a `retry_safe` takeover. Tool
    # classes implement `process_invocation` and do not override this method.
    #
    # Raif.config.model_tool_invocation_authorizer is called first, at execution
    # time, with the invocation (its tool, arguments and source). It vetoes the
    # call by raising. The exception is tagged with
    # Raif::Errors::ModelToolInvocationAuthorizationError and then handled like
    # any other tool exception by the caller.
    def execute_invocation(invocation)
      authorizer = Raif.config.model_tool_invocation_authorizer
      if authorizer
        begin
          authorizer.call(invocation: invocation)
        rescue StandardError => e
          e.extend(Raif::Errors::ModelToolInvocationAuthorizationError) unless e.is_a?(Raif::Errors::ModelToolInvocationAuthorizationError)
          raise
        end
      end

      process_invocation(invocation)
    end

    def invocation_partial_name
      name.gsub("Raif::ModelTools::", "").underscore
    end

    # Defines or retrieves the tool's argument schema.
    #
    # When defining:
    #   - arity-0 block with `dynamic: false`: static schema, built once at class load.
    #   - arity-0 block with `dynamic: true`: re-evaluated on every read.
    #   - arity-1 block (any `dynamic:` value): source-aware. Re-evaluated on
    #     every read and receives the caller `source` — typically the agent
    #     invoking the tool. Use this to gate fields on per-run context without
    #     reading global state. The `dynamic:` flag is implied for this form
    #     because a source-dependent schema must re-evaluate on each read.
    #
    # @param dynamic [Boolean] When true, the schema re-evaluates on each read.
    #   Automatically set to true for arity-1 blocks.
    # @param source [Object, nil] Passed into arity-1 schema blocks; ignored
    #   for static / arity-0 schemas.
    def tool_arguments_schema(dynamic: false, source: nil, &block)
      if block_given?
        # Arity-1 blocks are inherently source-dependent and must be dynamic.
        # Auto-promote so callers don't have to think about the interaction.
        dynamic = true if block.arity == 1
        json_schema_definition(:tool_arguments, dynamic: dynamic, &block)
      elsif schema_defined?(:tool_arguments)
        schema_for(:tool_arguments, source: source)
      else
        raise NotImplementedError,
          "#{name} must define tool arguments schema via tool_arguments_schema or override #{name}.tool_arguments_schema"
      end
    end

    # Backward-compatible entry point for rendering/validating a tool's schema
    # against a caller `source`. Raif's internals go through this helper (LLM
    # formatters, argument validation, argument stripping) rather than calling
    # `tool_arguments_schema(source: …)` directly so that subclasses whose
    # overrides predate the `source:` keyword keep working.
    #
    # If the tool's `tool_arguments_schema` accepts `source:` (the base
    # implementation, or an override that opted in), the helper forwards it.
    # Otherwise the helper falls back to the no-arg form — the schema simply
    # doesn't get per-call context, matching pre-source-aware behavior.
    #
    # @param source [Object, nil] The caller (typically the agent).
    # @return [Hash] The tool's JSON schema.
    def tool_arguments_schema_for_source(source)
      if method_accepts_source_kwarg?(:tool_arguments_schema)
        tool_arguments_schema(source: source)
      else
        tool_arguments_schema
      end
    end

    # Analogous backward-compatible entry point for `example_model_invocation`.
    def example_model_invocation_for_source(source)
      if method_accepts_source_kwarg?(:example_model_invocation)
        example_model_invocation(source: source)
      else
        example_model_invocation
      end
    end

    # Analogous backward-compatible entry point for `prepare_tool_arguments`.
    # Lets subclass overrides with the pre-source-aware signature
    # `def self.prepare_tool_arguments(arguments)` keep working.
    def prepare_tool_arguments_for_source(arguments, source)
      if method_accepts_source_kwarg?(:prepare_tool_arguments)
        prepare_tool_arguments(arguments, source: source)
      else
        prepare_tool_arguments(arguments)
      end
    end

    def provider_managed?
      false
    end

    def renderable?
      true
    end

    # The content of the tool-call-result message that gets sent back to the
    # model on subsequent turns. Called lazily at message-build time on every
    # turn — overrides can return live state (e.g. a follow-on record's status)
    # rather than a static snapshot. The default is the invocation's raw
    # `result` jsonb, which is what most tools want.
    #
    # @param invocation [Raif::ModelToolInvocation]
    # @return [Object] anything serializable into the tool-call-result message
    #   (string, hash, etc.). Returning nil or "" falls back to the raw result.
    def format_result_for_llm(invocation)
      invocation.result
    end

    # When true, Raif creates a synthetic follow-up entry after this invocation
    # finalizes, prompting the model again immediately so it can react to the
    # tool result in the same conversational turn. Use for tools whose result
    # the model needs to keep reasoning over (search → read → act). Skip for
    # tools whose result is interesting only on a later turn (e.g. queueing a
    # suggestion the user will review later).
    #
    # Instance-aware so a tool can decide based on what actually happened
    # (e.g. "fire only on partial failure"). Default: false.
    #
    # @param invocation [Raif::ModelToolInvocation]
    # @return [Boolean]
    def triggers_immediate_llm_follow_up?(invocation)
      false
    end

    # Declares that the tool does not produce its result before `process_invocation`
    # returns. `process_invocation` starts the work (enqueues a job, calls a slow
    # service) and returns; the invocation stays unfinished, and the agent or
    # conversation waits without making a model call, until host code calls
    # `invocation.complete!(result)` or `invocation.fail!(message)`.
    #
    # `process_invocation` can run a second time if its job is retried before it
    # returns, so start the work idempotently: `invocation.id` is a stable key.
    # A tool that is also `retry_safe` can be taken over only while
    # `process_invocation` runs, never during the wait for the host.
    #
    #   class SlowLookup < Raif::ModelTool
    #     defers_completion deadline: 45.minutes
    #
    #     def self.process_invocation(invocation)
    #       SlowLookupJob.perform_later(invocation)
    #     end
    #   end
    #
    # @param deadline [ActiveSupport::Duration, nil] how long to wait before the model
    #   gets an error result for the call. Defaults to
    #   Raif.config.deferred_model_tool_invocation_deadline.
    def defers_completion(deadline: nil)
      @deferred_completion = true
      @invocation_deadline = deadline if deadline.present?
    end

    # Declared on the class or inherited from a superclass.
    def deferred_completion?
      return @deferred_completion unless @deferred_completion.nil?

      superclass.respond_to?(:deferred_completion?) && superclass.deferred_completion?
    end

    # Overrides the deadline of the tool's invocations.
    def invocation_deadline(deadline = nil)
      @invocation_deadline = deadline if deadline.present?
      return @invocation_deadline if @invocation_deadline.present?

      inherited = superclass.declared_invocation_deadline if superclass.respond_to?(:declared_invocation_deadline)
      return inherited if inherited.present?

      if deferred_completion?
        Raif.config.deferred_model_tool_invocation_deadline
      else
        Raif.config.model_tool_invocation_deadline
      end
    end

    # Declares that running the tool a second time for the same invocation is
    # harmless (a read, or a write keyed on `invocation.id`). Raif then lets a
    # later execution take over an invocation whose first execution was
    # abandoned, once `lease` has passed since it started. The lease must be
    # longer than the tool can run. Without this declaration Raif never runs a
    # tool twice for one invocation.
    def retry_safe(lease: 2.minutes)
      @retry_safe = true
      @execution_lease = lease
    end

    def retry_safe?
      return @retry_safe unless @retry_safe.nil?

      superclass.respond_to?(:retry_safe?) && superclass.retry_safe?
    end

    # How long one execution holds its claim on an invocation.
    def execution_lease
      return @execution_lease if @execution_lease.present?
      return superclass.execution_lease if retry_safe? && superclass.respond_to?(:retry_safe?) && superclass.retry_safe?

      invocation_deadline
    end

    def declared_invocation_deadline
      return @invocation_deadline if @invocation_deadline.present?

      superclass.declared_invocation_deadline if superclass.respond_to?(:declared_invocation_deadline)
    end

    # Builds the invocation row for a tool call without running the tool.
    def build_invocation(provider_tool_call_id:, tool_arguments:, source:, **attributes)
      Raif::ModelToolInvocation.new(
        provider_tool_call_id: provider_tool_call_id,
        source: source,
        tool_type: name,
        tool_arguments: prepare_tool_arguments_for_source(tool_arguments, source),
        completion_mode: deferred_completion? ? "deferred" : "automatic",
        **attributes
      )
    end

    def invoke_tool(provider_tool_call_id:, tool_arguments:, source:)
      prepared_arguments = prepare_tool_arguments_for_source(tool_arguments, source)

      tool_invocation = Raif::ModelToolInvocation.create!(
        provider_tool_call_id: provider_tool_call_id,
        source: source,
        tool_type: name,
        tool_arguments: prepared_arguments
      )

      # Not wrapped in a transaction: tools make network calls, which would hold a
      # transaction open for their whole duration, and on PostgreSQL one failed
      # statement inside it aborts every later query the tool makes. A tool that
      # needs its writes to be atomic opens its own transaction.
      execute_invocation(tool_invocation)
      # Skip validation: a source-aware schema can change during the run, and a
      # silently failed write breaks the agent's pairing of results to invocations.
      # save! (not update_columns) also persists a result the tool set in memory.
      tool_invocation.completed_at = Time.current
      tool_invocation.save!(validate: false)
      tool_invocation
    rescue StandardError => e
      if tool_invocation&.persisted?
        tool_invocation.failed_at = Time.current
        tool_invocation.save!(validate: false)
      end
      raise e
    end

    # Prepares tool arguments before validation and invocation. Override in subclasses
    # to add tool-specific argument processing (e.g. type coercion, default injection).
    # The base implementation strips keys not declared in the tool's argument schema,
    # which handles LLMs that hallucinate extra parameters.
    #
    # @param arguments [Hash] The raw tool arguments from the LLM response
    # @param source [Object, nil] The caller invoking the tool (e.g. the agent).
    #   Forwarded into the schema lookup so source-aware schemas are evaluated
    #   against the same context the model saw when selecting the tool.
    # @return [Hash] The prepared arguments ready for validation and processing
    def prepare_tool_arguments(arguments, source: nil)
      strip_unknown_tool_arguments(arguments, source: source)
    end

  private

    # True iff `method_name` (a class method on self) accepts a `source:`
    # keyword argument — either as a named kwarg or via a kwarg-rest (`**`).
    # Used to keep subclass overrides that predate the `source:` keyword
    # working.
    def method_accepts_source_kwarg?(method_name)
      method(method_name).parameters.any? do |type, name|
        (type == :key || type == :keyreq) && name == :source || type == :keyrest
      end
    end

    # Removes keys from the arguments hash that are not declared in the tool's
    # argument schema. Logs a warning when keys are stripped so hallucination
    # patterns can be monitored. Normalizes all keys to strings for consistent
    # comparison since the schema builder uses symbol keys and LLM responses
    # use string keys.
    #
    # @param arguments [Hash] The raw tool arguments
    # @param source [Object, nil] Forwarded into source-aware schema evaluation.
    # @return [Hash] The arguments with only schema-declared keys
    def strip_unknown_tool_arguments(arguments, source: nil)
      return arguments unless arguments.is_a?(Hash)

      schema = tool_arguments_schema_for_source(source)
      schema_properties = schema[:properties] || schema["properties"]
      return arguments if schema_properties.blank?

      normalized_arguments = arguments.deep_stringify_keys
      allowed_keys = schema_properties.keys.map(&:to_s)
      dropped_keys = normalized_arguments.keys - allowed_keys

      if dropped_keys.any?
        Rails.logger.warn(
          "[Raif::ModelTool] Stripped unexpected tool arguments for #{name}: #{dropped_keys.join(", ")}"
        )
      end

      normalized_arguments.slice(*allowed_keys)
    end
  end

  # Instance method to get the tool arguments schema
  # For instance-dependent schemas, builds the schema with this instance as context
  # For class-level schemas, returns the class-level schema
  def tool_arguments_schema
    schema_for_instance(:tool_arguments)
  end

end
