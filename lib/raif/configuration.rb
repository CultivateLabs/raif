# frozen_string_literal: true

module Raif
  class Configuration
    CAPTURE_MODEL_COMPLETION_MODES = ["full", "summary", "none"].freeze
    OPEN_ROUTER_DATA_COLLECTION_VALUES = ["allow", "deny"].freeze

    attr_accessor :agent_types,
      :anthropic_api_key,
      :archive_enabled,
      :archive_partition_column,
      :archive_partition_fallback,
      :archive_storage,
      :anthropic_message_batches_beta_header,
      :bedrock_models_enabled,
      :anthropic_models_enabled,
      :authorize_admin_controller_action,
      :authorize_controller_action,
      :aws_bedrock_model_name_prefix,
      :aws_bedrock_region,
      :bedrock_embedding_models_enabled,
      :conversation_entries_controller,
      :conversation_entry_max_retries,
      :conversation_llm_messages_max_length_default,
      :conversation_system_prompt_intro,
      :conversation_types,
      :conversations_controller,
      :current_user_method,
      :default_embedding_model_key,
      :default_llm_model_key,
      :evals_capture_model_completions,
      :evals_concurrency,
      :evals_default_llm_judge_model_key,
      :evals_verbose_output,
      :google_api_key,
      :google_embedding_models_enabled,
      :google_models_enabled,
      :inference_cost_event_metadata,
      :inference_cost_events_enabled,
      :llm_api_requests_enabled,
      :llm_request_max_retries,
      :llm_request_retriable_exceptions,
      :model_completion_authorizer,
      :model_completion_batch_max_age,
      :model_completion_batch_poll_schedule,
      :model_completion_retention_period,
      :model_superclass,
      :open_ai_api_key,
      :open_ai_batch_completion_window,
      :open_ai_api_version,
      :open_ai_auth_header_style,
      :open_ai_base_url,
      :open_ai_embedding_base_url,
      :open_ai_embedding_models_enabled,
      :open_ai_models_enabled,
      :open_ai_store_responses,
      :open_router_api_key,
      :open_router_data_collection,
      :open_router_models_enabled,
      :open_router_zdr,
      :open_router_app_name,
      :open_router_site_url,
      :request_open_timeout,
      :request_read_timeout,
      :request_write_timeout,
      :streaming_unsupported_model_keys,
      :streaming_update_chunk_size_threshold,
      :task_creator_optional,
      :task_retention_period,
      :prompt_studio_runs_enabled,
      :task_system_prompt_intro,
      :user_tool_types,
      :x_ai_api_key,
      :x_ai_base_url,
      :x_ai_models_enabled

    alias_method :anthropic_bedrock_models_enabled, :bedrock_models_enabled
    alias_method :anthropic_bedrock_models_enabled=, :bedrock_models_enabled=

    alias_method :aws_bedrock_titan_embedding_models_enabled, :bedrock_embedding_models_enabled
    alias_method :aws_bedrock_titan_embedding_models_enabled=, :bedrock_embedding_models_enabled=

    def initialize
      @agent_types = Set.new(["Raif::Agents::NativeToolCallingAgent"])
      @anthropic_api_key = default_disable_llm_api_requests? ? "placeholder-anthropic-api-key" : ENV["ANTHROPIC_API_KEY"]
      @anthropic_message_batches_beta_header = "message-batches-2024-09-24"
      @bedrock_models_enabled = false
      @anthropic_models_enabled = ENV["ANTHROPIC_API_KEY"].present?
      @authorize_admin_controller_action = ->{ false }
      @authorize_controller_action = ->{ false }
      @aws_bedrock_region = "us-east-1"
      @aws_bedrock_model_name_prefix = "us"
      # Master switch for the archive-and-cull capability. Explicit opt-in
      # only: with the default false (and no archive_storage adapter),
      # upgrading the gem never deletes anything.
      @archive_enabled = false
      # Column on the archived resource (e.g. :account_id) whose value
      # partitions archive objects: every object then holds records from
      # exactly one partition and is stored under a per-partition key
      # prefix, so Raif::Archive.purge_partition! can completely erase one
      # partition's archives. nil (the default) preserves unpartitioned
      # behavior. The column's value must be immutable for the record's
      # lifetime. Column existence is validated when the archive job or
      # dry_run executes, not at boot.
      @archive_partition_column = nil
      # Applies only when archive_partition_column is set: what to do with a
      # record whose partition value is NULL or normalizes to blank. nil
      # (the default) fails closed: the record is never archived, so a later
      # partition purge cannot miss records that lost their attribution.
      # Hosts with intentionally global/unowned records may explicitly set
      # Raif::ArchivePartition::UNGROUPED (aliased as Raif::Archive::UNGROUPED
      # for post-boot callers) to archive them under the reserved
      # "_ungrouped" storage segment, which purge_partition! never touches.
      @archive_partition_fallback = nil
      # Storage adapter instance implementing
      # write(key:, io:, checksum_sha256:), returning a location string and
      # raising on any failure. See Raif::ArchiveStorage::FileSystem for a
      # reference implementation; production hosts typically supply their own
      # (e.g. S3-backed) adapter.
      @archive_storage = nil
      @bedrock_embedding_models_enabled = false
      @task_system_prompt_intro = "You are a helpful assistant."
      @conversation_entries_controller = "Raif::ConversationEntriesController"
      @conversation_entry_max_retries = 2
      @conversation_llm_messages_max_length_default = 50
      @conversation_system_prompt_intro = "You are a helpful assistant who is collaborating with a teammate."
      @conversation_types = Set.new(["Raif::Conversation"])
      @conversations_controller = "Raif::ConversationsController"
      @current_user_method = :current_user
      @default_embedding_model_key = "open_ai_text_embedding_3_small"
      @default_llm_model_key = default_disable_llm_api_requests? ? :raif_test_llm : (ENV["RAIF_DEFAULT_LLM_MODEL_KEY"].presence || "open_ai_gpt_4o")
      # :full captures every prompt, message, and response - what you want debugging one eval,
      # unmanageable for a dataset run. :summary keeps tokens and cost, :none omits the
      # per-call array. Usage totals are identical in all three modes.
      @evals_capture_model_completions = :full
      # How many eval executions run at once. An eval run is almost entirely waiting on provider
      # responses, so this is the wall clock. Serial by default: raising it needs a database
      # connection pool larger than the concurrency, and enough provider rate limit to absorb it.
      @evals_concurrency = 1
      # Unset means judging falls back to default_llm_model_key, so the model under test grades its
      # own output and a run against a second model changes the judge with it, which
      # Raif::Evals::Run warns about.
      @evals_default_llm_judge_model_key = ENV["RAIF_EVALS_DEFAULT_LLM_JUDGE_MODEL_KEY"].presence
      @evals_verbose_output = false
      google_api_key = ENV["GOOGLE_AI_API_KEY"].presence || ENV["GOOGLE_API_KEY"]
      @google_api_key = default_disable_llm_api_requests? ? "placeholder-google-api-key" : google_api_key
      @google_embedding_models_enabled = false
      @google_models_enabled = @google_api_key.present?
      # Optional callable receiving a model_completion: keyword argument and
      # returning a hash merged into Raif::InferenceCostEvent#metadata at sync
      # time. The sanctioned host extension point for attaching app-specific
      # context (e.g. account/workflow ids) to cost events.
      @inference_cost_event_metadata = nil
      # When true, a durable Raif::InferenceCostEvent is created for each
      # model completion that reaches a terminal state (completed or failed).
      @inference_cost_events_enabled = true
      @llm_api_requests_enabled = !default_disable_llm_api_requests?
      @llm_request_max_retries = 2
      @llm_request_retriable_exceptions = [
        Faraday::ConnectionFailed,
        Faraday::TimeoutError,
        Faraday::ServerError,
        # 429. A ClientError rather than a ServerError, so it is not covered above, and the
        # transient failure that gets more likely the more requests are in flight at once.
        Faraday::TooManyRequestsError,
        Net::ReadTimeout,
        Net::OpenTimeout,
        Raif::Errors::BlankResponseError,
      ]
      # Schedule for the self-rescheduling Raif::PollModelCompletionBatchJob.
      # The Nth poll waits poll_schedule[N] (clamped to the last entry once exhausted).
      @model_completion_batch_poll_schedule = [
        60.seconds,
        2.minutes,
        5.minutes,
        10.minutes,
        30.minutes
      ]
      # Optional lambda called with llm:/source: keyword args at the start of
      # Raif::Llm#chat, before the Raif::ModelCompletion is created or any
      # provider API call is made. Raise from it to veto the request (e.g. a
      # host app enforcing per-account usage limits); the exception propagates
      # to the caller. Return values are ignored. Does not apply to embedding
      # generation or batch API submissions.
      @model_completion_authorizer = nil
      # Hard ceiling for any non-terminal Raif::ModelCompletionBatch. Older
      # batches are expired by the hourly safety sweep
      # (Raif::ExpireStuckModelCompletionBatchesJob) and the polling job's
      # max_age_exceeded? branch: a best-effort provider-side cancel is issued
      # via batch.cancel! before the batch is force-failed locally, so the
      # workflow can advance and we stop paying for completions we won't read.
      # If the cancel fails (network, 5xx, etc.), the local force-fail still
      # happens and the provider-side batch may continue and be billed.
      @model_completion_batch_max_age = 26.hours
      # How long completed/failed Raif::ModelCompletion rows are retained
      # before Raif::ArchiveModelCompletionsJob archives and deletes them
      # (e.g. 6.months). nil (the default) disables model completion culling
      # even when archive_enabled is true. validate! rejects values below
      # 1.month: cost and budget consumers aggregate by billing period, so an
      # accidentally tiny retention value must never be able to eat rows out
      # from under an open billing window.
      @model_completion_retention_period = nil
      @model_superclass = "ApplicationRecord"
      @open_ai_api_key = default_disable_llm_api_requests? ? "placeholder-open-ai-api-key" : ENV["OPENAI_API_KEY"]
      @open_ai_api_version = nil
      @open_ai_batch_completion_window = "24h"
      @open_ai_auth_header_style = :bearer
      @open_ai_base_url = "https://api.openai.com/v1"
      @open_ai_embedding_base_url = "https://api.openai.com/v1"
      @open_ai_embedding_models_enabled = ENV["OPENAI_API_KEY"].present?
      @open_ai_models_enabled = ENV["OPENAI_API_KEY"].present?
      # Value of the `store` parameter on every OpenAI Responses API request.
      # The provider defaults it to true and then keeps the response object for
      # 30 days, so the prompt becomes readable in the OpenAI dashboard and
      # retrievable by response id. Raif defaults to false, because an engine
      # cannot know whether its host app is allowed to leave prompts with a
      # processor. Set it to true to get that visibility and provider-side
      # response retrieval back.
      #
      # false is not zero retention. OpenAI still generates abuse monitoring
      # logs for all API usage and holds them for up to 30 days, unless the
      # organization is approved for Zero Data Retention or Modified Abuse
      # Monitoring. Under Zero Data Retention `store` is always treated as
      # false, so setting this to true has no effect there.
      #
      # Only the Responses API is affected: `store` already defaults to false
      # on Chat Completions, so Raif::Llms::OpenAiCompletions sends nothing.
      @open_ai_store_responses = false
      open_router_api_key = ENV["OPEN_ROUTER_API_KEY"].presence || ENV["OPENROUTER_API_KEY"]
      @open_router_api_key = default_disable_llm_api_requests? ? "placeholder-open-router-api-key" : open_router_api_key
      # Value of `provider.data_collection` on every OpenRouter request.
      # OpenRouter routes a request to an upstream inference provider, and some
      # of those providers store prompts non-transiently and train on them.
      # OpenRouter defaults the parameter to "allow", which filters nothing, so
      # the only thing standing between a prompt and such a provider is the
      # account-level privacy setting on openrouter.ai, which the host app
      # cannot see from its own code. "deny" (the Raif default) routes only to
      # providers that do not collect user data.
      #
      # "deny" is about training and non-transient storage, not retention:
      # OpenRouter states it has no routing rules based on provider retention
      # policies, so a provider that holds prompts for a fixed window without
      # training on them still qualifies. Use open_router_zdr below for
      # retention.
      @open_router_data_collection = "deny"
      # Value of `provider.zdr` on OpenRouter requests. true restricts routing
      # to endpoints with a Zero Data Retention policy, which is the only
      # OpenRouter control that stops an upstream provider retaining the
      # prompt. Defaults to false, because it is a much narrower filter than
      # data_collection and many models have no ZDR endpoint at all - a
      # restrictive default would turn working models into 404s on upgrade.
      # The parameter is only sent when true: OpenRouter documents false and
      # absent as identical, and per-request ZDR is OR'd with the account-wide
      # and guardrail settings, so it can only add enforcement.
      @open_router_zdr = false
      @open_router_models_enabled = @open_router_api_key.present?
      @prompt_studio_runs_enabled = Rails.env.development?
      @open_router_app_name = nil
      @open_router_site_url = nil
      @request_open_timeout = nil
      @request_read_timeout = nil
      @request_write_timeout = nil
      # Raif model keys whose streaming path is known to be unreliable. When a
      # caller passes a block to Raif::Llm#chat for one of these models, Raif
      # transparently falls back to the non-streaming path. Each entry may be
      # a String, Symbol, or Regexp matched against the model key.
      #
      # Default covers Bedrock gpt-oss, whose Converse streaming endpoint
      # delivers corrupted/truncated tool_use deltas. Set to [] to disable
      # the workaround.
      @streaming_unsupported_model_keys = [/\Abedrock_gpt_oss_/]
      @streaming_update_chunk_size_threshold = 25
      @task_creator_optional = true
      # How long Raif::Task rows are retained before Raif::ArchiveTasksJob
      # archives and deletes them (e.g. 12.months). nil (the default)
      # disables task culling even when archive_enabled is true. Independent
      # of model_completion_retention_period, and validated against the same
      # 1.month floor.
      #
      # A task is never culled while its Raif::ModelCompletion row survives,
      # so setting this below model_completion_retention_period does not cull
      # tasks any earlier - it just makes the completion's window govern both.
      @task_retention_period = nil
      @user_tool_types = []
      x_ai_api_key = ENV["XAI_API_KEY"].presence || ENV["X_AI_API_KEY"]
      @x_ai_api_key = default_disable_llm_api_requests? ? "placeholder-x-ai-api-key" : x_ai_api_key
      @x_ai_base_url = "https://api.x.ai/v1"
      @x_ai_models_enabled = @x_ai_api_key.present?
    end

    def validate!
      # Before the LLM-registry early return below: archive validation guards
      # a destructive path (culling), so a node with no LLM API keys (e.g. a
      # misconfigured cron/worker box) must still have its archive settings
      # validated.
      validate_archive_config!

      # Also before the early return: a typo in a data retention setting must
      # fail loudly rather than silently fall back to the provider default,
      # which is the permissive one for both providers.
      validate_provider_data_retention_config!

      if Raif.llm_registry.blank?
        puts <<~EOS

          !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
          No LLMs are enabled in Raif. Make sure you have an API key configured for at least one LLM provider. You can do this by setting an API key in your environment variables or in config/initializers/raif.rb (e.g. ENV["OPENAI_API_KEY"], ENV["ANTHROPIC_API_KEY"], ENV["OPEN_ROUTER_API_KEY"]).

          See the README for more information: https://github.com/CultivateLabs/raif#setup
          !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

        EOS

        return
      end

      unless Raif.available_llm_keys.include?(default_llm_model_key.to_sym)
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.default_llm_model_key was set to #{default_llm_model_key}, but must be one of: #{Raif.available_llm_keys.join(", ")}"
      end

      if default_embedding_model_key.present? &&
          Raif.embedding_model_registry.present? &&
          !Raif.available_embedding_model_keys.include?(default_embedding_model_key.to_sym)
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.default_embedding_model_key was set to #{default_embedding_model_key}, but must be one of: #{Raif.available_embedding_model_keys.join(", ")}" # rubocop:disable Layout/LineLength
      end

      if authorize_controller_action.respond_to?(:call)
        authorize_controller_action.freeze
      else
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.authorize_controller_action must respond to :call and return a boolean"
      end

      if authorize_admin_controller_action.respond_to?(:call)
        authorize_admin_controller_action.freeze
      else
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.authorize_admin_controller_action must respond to :call and return a boolean"
      end

      if model_completion_authorizer.nil? || model_completion_authorizer.respond_to?(:call)
        model_completion_authorizer&.freeze
      else
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.model_completion_authorizer must be nil or respond to :call"
      end

      unless CAPTURE_MODEL_COMPLETION_MODES.include?(evals_capture_model_completions.to_s)
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.evals_capture_model_completions was set to #{evals_capture_model_completions.inspect}, but must be one of: #{CAPTURE_MODEL_COMPLETION_MODES.join(", ")}" # rubocop:disable Layout/LineLength
      end

      if open_ai_models_enabled && open_ai_api_key.blank?
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.open_ai_api_key is required when Raif.config.open_ai_models_enabled is true. Set it via Raif.config.open_ai_api_key or ENV[\"OPENAI_API_KEY\"]" # rubocop:disable Layout/LineLength
      end

      if open_ai_models_enabled && ![:bearer, :api_key].include?(open_ai_auth_header_style)
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.open_ai_auth_header_style must be either :bearer or :api_key"
      end

      if open_ai_embedding_models_enabled && open_ai_api_key.blank?
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.open_ai_api_key is required when Raif.config.open_ai_embedding_models_enabled is true. Set it via Raif.config.open_ai_api_key or ENV[\"OPENAI_API_KEY\"]" # rubocop:disable Layout/LineLength
      end

      if anthropic_models_enabled && anthropic_api_key.blank?
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.anthropic_api_key is required when Raif.config.anthropic_models_enabled is true. Set it via Raif.config.anthropic_api_key or ENV['ANTHROPIC_API_KEY']" # rubocop:disable Layout/LineLength
      end

      if open_router_models_enabled && open_router_api_key.blank?
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.open_router_api_key is required when Raif.config.open_router_models_enabled is true. Set it via Raif.config.open_router_api_key or ENV['OPEN_ROUTER_API_KEY']" # rubocop:disable Layout/LineLength
      end

      if google_models_enabled && google_api_key.blank?
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.google_api_key is required when Raif.config.google_models_enabled is true. Set it via Raif.config.google_api_key or ENV['GOOGLE_API_KEY']" # rubocop:disable Layout/LineLength
      end

      if google_embedding_models_enabled && google_api_key.blank?
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.google_api_key is required when Raif.config.google_embedding_models_enabled is true. Set it via Raif.config.google_api_key or ENV['GOOGLE_API_KEY']" # rubocop:disable Layout/LineLength
      end

      if x_ai_models_enabled && x_ai_api_key.blank?
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.x_ai_api_key is required when Raif.config.x_ai_models_enabled is true. Set it via Raif.config.x_ai_api_key or ENV['XAI_API_KEY']" # rubocop:disable Layout/LineLength
      end
    end

  private

    def validate_provider_data_retention_config!
      unless [true, false].include?(open_ai_store_responses)
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.open_ai_store_responses must be true or false (got #{open_ai_store_responses.inspect})"
      end

      unless [true, false].include?(open_router_zdr)
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.open_router_zdr must be true or false (got #{open_router_zdr.inspect})"
      end

      return if OPEN_ROUTER_DATA_COLLECTION_VALUES.include?(open_router_data_collection.to_s)

      raise Raif::Errors::InvalidConfigError,
        "Raif.config.open_router_data_collection must be one of: #{OPEN_ROUTER_DATA_COLLECTION_VALUES.join(", ")} (got #{open_router_data_collection.inspect})" # rubocop:disable Layout/LineLength
    end

    def validate_archive_config!
      if archive_enabled && archive_storage.nil?
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.archive_storage is required when Raif.config.archive_enabled is true. Provide an adapter implementing write(key:, io:, checksum_sha256:) (see Raif::ArchiveStorage::FileSystem)" # rubocop:disable Layout/LineLength
      end

      if archive_storage.present? && !archive_storage.respond_to?(:write)
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.archive_storage must implement write(key:, io:, checksum_sha256:)"
      end

      unless archive_partition_column.nil? || archive_partition_column.is_a?(Symbol)
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.archive_partition_column must be a Symbol naming a column on the archived resource (got #{archive_partition_column.inspect})"
      end

      # Deliberately no database access here (table/column existence is
      # checked lazily by the archive job and dry_run): boot validation must
      # work on a blank database (db:create, db:migrate, asset precompile).
      unless archive_partition_fallback.nil? || archive_partition_fallback.equal?(Raif::ArchivePartition::UNGROUPED)
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.archive_partition_fallback must be nil (fail closed) or Raif::ArchivePartition::UNGROUPED (got #{archive_partition_fallback.inspect})" # rubocop:disable Layout/LineLength
      end

      # Billing-window floor, enforced whether or not archiving is enabled: a
      # misconfigured retention value must never be able to reach inside an
      # open billing period.
      if model_completion_retention_period.present? && model_completion_retention_period < 1.month
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.model_completion_retention_period must be at least 1 month (got #{model_completion_retention_period.inspect})"
      end

      return if task_retention_period.blank? || task_retention_period >= 1.month

      raise Raif::Errors::InvalidConfigError,
        "Raif.config.task_retention_period must be at least 1 month (got #{task_retention_period.inspect})"
    end

    # By default, evals run in the test environment, but need real API keys.
    # In normal tests, we insert placeholders to make it hard to accidentally rack up an LLM API bill.
    def default_disable_llm_api_requests?
      Rails.env.test? && !Raif.running_evals?
    end

  end
end
