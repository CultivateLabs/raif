# frozen_string_literal: true

Raif.configure do |config|
  # Your OpenAI API key. Defaults to ENV["OPENAI_API_KEY"]
  # config.open_ai_api_key = ENV["OPENAI_API_KEY"]

  # Whether OpenAI models are enabled.
  # config.open_ai_models_enabled = ENV["OPENAI_API_KEY"].present?

  # Whether OpenAI embedding models are enabled.
  # config.open_ai_embedding_models_enabled = ENV["OPENAI_API_KEY"].present?

  # The base URL for OpenAI API requests.
  # Set this if you want to use the OpenAI adapter with a different provider (e.g. for using Azure instead of OpenAI)
  # config.open_ai_base_url = "https://api.openai.com/v1"

  # The base URL for OpenAI embedding API requests.
  # Set this if you want to use a different provider for embeddings (e.g. Ollama, vLLM, or other OpenAI-compatible APIs)
  # config.open_ai_embedding_base_url = "https://api.openai.com/v1"

  # When set, this will be included as an api-version parameter in any OpenAI API requests (e.g. for using Azure instead of OpenAI)
  # config.open_ai_api_version = nil

  # The authentication header style for OpenAI API requests. Defaults to :bearer
  # Use :bearer for standard OpenAI API (Authorization: Bearer <token>)
  # Use :api_key for Azure OpenAI API (api-key: <token>)
  # config.open_ai_auth_header_style = :bearer

  # Value of the `store` parameter on OpenAI Responses API requests. Defaults to false.
  # OpenAI defaults it to true and then retains the request, which makes the prompt
  # readable in the OpenAI dashboard and logs. Set it to true to get that visibility
  # and provider-side response retrieval back.
  # Override it per Raif::Task/Raif::Conversation/Raif::Agent subclass, or per
  # Raif::Llm#chat call, with the open_ai_store_responses keyword.
  # config.open_ai_store_responses = false

  # Your Anthropic API key. Defaults to ENV["ANTHROPIC_API_KEY"]
  # config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]

  # Whether Anthropic models are enabled.
  # config.anthropic_models_enabled = ENV["ANTHROPIC_API_KEY"].present?

  # Whether Anthropic models via AWS Bedrock are enabled. Defaults to false
  # config.bedrock_models_enabled = false

  # The AWS Bedrock region to use. Defaults to "us-east-1"
  # config.aws_bedrock_region = "us-east-1"

  # Prefix to apply to the model name in AWS Bedrock API calls (e.g. us.anthropic.claude-3-5-haiku-20241022-v1:0)
  # config.aws_bedrock_model_name_prefix = "us"

  # Whether Titan embedding models are enabled. Defaults to false
  # config.bedrock_embedding_models_enabled = false

  # Your OpenRouter API key. Defaults to ENV["OPEN_ROUTER_API_KEY"]
  # config.open_router_api_key = ENV["OPEN_ROUTER_API_KEY"]

  # Whether OpenRouter models are enabled.
  # config.open_router_models_enabled = ENV["OPEN_ROUTER_API_KEY"].present?

  # The app name to include in OpenRouter API requests headers. Optional.
  # config.open_router_app_name = "My App"

  # The site URL to include in OpenRouter API requests headers. Optional.
  # config.open_router_site_url = "https://myapp.com"

  # Value of `provider.data_collection` on OpenRouter requests. Defaults to "deny".
  # OpenRouter routes each request to an upstream inference provider, and some of them
  # log prompts and train on them. "deny" restricts routing to providers that do not
  # store prompts; "allow" permits any provider.
  # Override it per Raif::Task/Raif::Conversation/Raif::Agent subclass, or per
  # Raif::Llm#chat call, with the open_router_data_collection keyword.
  # config.open_router_data_collection = "deny"

  # Your Google AI API key. Defaults to ENV["GOOGLE_AI_API_KEY"].presence || ENV["GOOGLE_API_KEY"]
  # config.google_api_key = ENV["GOOGLE_AI_API_KEY"].presence || ENV["GOOGLE_API_KEY"]

  # Whether Google models are enabled.
  # config.google_models_enabled = ENV["GOOGLE_AI_API_KEY"].present? || ENV["GOOGLE_API_KEY"].present?

  # Whether Google embedding models are enabled. Defaults to false
  # config.google_embedding_models_enabled = false

  # Your xAI API key. Defaults to ENV["XAI_API_KEY"].presence || ENV["X_AI_API_KEY"]
  # config.x_ai_api_key = ENV["XAI_API_KEY"].presence || ENV["X_AI_API_KEY"]

  # Whether xAI models are enabled.
  # config.x_ai_models_enabled = ENV["XAI_API_KEY"].present? || ENV["X_AI_API_KEY"].present?

  # The default LLM model to use. Defaults to "open_ai_gpt_4o"
  # Available keys:
  #   open_ai_gpt_5_6_sol
  #   open_ai_gpt_5_6_terra
  #   open_ai_gpt_5_6_luna
  #   open_ai_gpt_5_5
  #   open_ai_gpt_5_4
  #   open_ai_gpt_5_4_mini
  #   open_ai_gpt_5_4_nano
  #   open_ai_gpt_5_3
  #   open_ai_gpt_5_2
  #   open_ai_gpt_5_1
  #   open_ai_gpt_5
  #   open_ai_gpt_5_mini
  #   open_ai_gpt_5_nano
  #   open_ai_gpt_4_1
  #   open_ai_gpt_4_1_mini
  #   open_ai_gpt_4_1_nano
  #   open_ai_gpt_4o
  #   open_ai_gpt_4o_mini
  #   open_ai_gpt_3_5_turbo
  #   open_ai_o4_mini
  #   open_ai_o3
  #   open_ai_o3_mini
  #   open_ai_o1
  #   open_ai_responses_gpt_5_6_sol
  #   open_ai_responses_gpt_5_6_terra
  #   open_ai_responses_gpt_5_6_luna
  #   open_ai_responses_gpt_5_5
  #   open_ai_responses_gpt_5_5_pro
  #   open_ai_responses_gpt_5_4
  #   open_ai_responses_gpt_5_4_pro
  #   open_ai_responses_gpt_5_4_mini
  #   open_ai_responses_gpt_5_4_nano
  #   open_ai_responses_gpt_5_3
  #   open_ai_responses_gpt_5_2
  #   open_ai_responses_gpt_5_2_pro
  #   open_ai_responses_gpt_5_1
  #   open_ai_responses_gpt_5
  #   open_ai_responses_gpt_5_pro
  #   open_ai_responses_gpt_5_mini
  #   open_ai_responses_gpt_5_nano
  #   open_ai_responses_gpt_4_1
  #   open_ai_responses_gpt_4_1_mini
  #   open_ai_responses_gpt_4_1_nano
  #   open_ai_responses_gpt_4o
  #   open_ai_responses_gpt_4o_mini
  #   open_ai_responses_gpt_3_5_turbo
  #   open_ai_responses_o4_mini
  #   open_ai_responses_o3
  #   open_ai_responses_o3_pro
  #   open_ai_responses_o3_mini
  #   open_ai_responses_o1
  #   open_ai_responses_o1_pro
  #   anthropic_claude_5_fable
  #   anthropic_claude_5_sonnet
  #   anthropic_claude_4_8_opus
  #   anthropic_claude_4_7_opus
  #   anthropic_claude_4_6_opus
  #   anthropic_claude_4_6_sonnet
  #   anthropic_claude_4_5_opus
  #   anthropic_claude_4_5_sonnet
  #   anthropic_claude_4_5_haiku
  #   anthropic_claude_4_1_opus
  #   bedrock_claude_5_fable
  #   bedrock_claude_5_sonnet
  #   bedrock_claude_4_8_opus
  #   bedrock_claude_4_7_opus
  #   bedrock_claude_4_6_opus
  #   bedrock_claude_4_6_sonnet
  #   bedrock_claude_4_5_opus
  #   bedrock_claude_4_5_sonnet
  #   bedrock_claude_4_5_haiku
  #   bedrock_claude_4_1_opus
  #   bedrock_claude_4_sonnet
  #   bedrock_claude_3_7_sonnet
  #   bedrock_claude_3_5_sonnet
  #   bedrock_amazon_nova_micro
  #   bedrock_amazon_nova_lite
  #   bedrock_amazon_nova_pro
  #   bedrock_deepseek_v3_2
  #   bedrock_deepseek_r1
  #   bedrock_gpt_oss_120b
  #   bedrock_gpt_oss_20b
  #   open_router_claude_5_fable
  #   open_router_claude_5_sonnet
  #   open_router_claude_4_8_opus
  #   open_router_deepseek_chat_v3
  #   open_router_deepseek_v3_1
  #   open_router_deepseek_v3_2
  #   open_router_gemini_3_5_flash
  #   open_router_gemini_3_1_pro_preview
  #   open_router_gemini_3_1_flash_lite_preview
  #   open_router_gemini_2_5_flash
  #   open_router_gemini_2_5_pro
  #   open_router_grok_4_20
  #   open_router_grok_4_5
  #   open_router_kimi_k2_thinking
  #   open_router_kimi_k2_5
  #   open_router_llama_3_1_8b_instruct
  #   open_router_llama_3_3_70b_instruct
  #   open_router_llama_4_maverick
  #   open_router_llama_4_scout
  #   open_router_minimax_m2
  #   open_router_minimax_m2_1
  #   open_router_minimax_m2_5
  #   open_router_mistral_large_3_2512
  #   open_router_mistral_small_3_2_24b
  #   open_router_open_ai_gpt_oss_120b
  #   open_router_open_ai_gpt_oss_20b
  #   open_router_google_gemma_4_31b_it
  #   x_ai_grok_4_5
  #   x_ai_grok_4_3
  #   x_ai_grok_4_20_reasoning
  #   x_ai_grok_4_20_non_reasoning
  #   google_gemini_3_5_flash
  #   google_gemini_3_1_pro
  #   google_gemini_3_1_flash_lite
  #   google_gemini_3_0_flash
  #   google_gemini_2_5_pro
  #   google_gemini_2_5_flash
  #
  # config.default_llm_model_key = "open_ai_gpt_4o"

  # The default embedding model to use when calling Raif.generate_embedding!
  # Defaults to "open_ai_text_embedding_3_small"
  # Available keys:
  #   open_ai_text_embedding_3_small
  #   open_ai_text_embedding_3_large
  #   open_ai_text_embedding_ada_002
  #   bedrock_titan_embed_text_v2
  #   google_gemini_embedding_2
  #
  # config.default_embedding_model_key = "open_ai_text_embedding_3_small"

  # A lambda that returns true if the current user is authorized to access admin controllers.
  # By default it returns false, so you must implement this in your application to use the admin controllers.
  # If your application's user model has an admin? method, you could use something like this:
  # config.authorize_admin_controller_action = ->{ current_user&.admin? }

  # A lambda that returns true if the current user is authorized to access non-admin controllers.
  # By default it returns false, so you must implement this in your application to use the non-admin controllers.
  # If you wanted to allow access to all logged in users, you could use something like this:
  # config.authorize_controller_action = ->{ current_user.present? }

  # The system prompt intro for Raif::Task instances. Defaults to "You are a helpful assistant."
  # config.task_system_prompt_intro = "You are a helpful assistant."
  # Or you can use a lambda to return a dynamic system prompt intro:
  # config.task_system_prompt_intro = ->(task){ "You are a helpful assistant. Today's date is #{Date.today.strftime('%B %d, %Y')}." }

  # Whether the creator association is optional for Raif::Task. Defaults to true.
  # config.task_creator_optional = true

  # The system prompt intro for Raif::Conversation instances. Defaults to "You are a helpful assistant who is collaborating with a teammate."
  # config.conversation_system_prompt_intro = "You are a helpful assistant who is collaborating with a teammate."
  # Or you can use a lambda to return a dynamic system prompt intro:
  # config.conversation_system_prompt_intro = ->(conversation){ "You are a helpful assistant talking to #{conversation.creator.email}. Today's date is #{Date.today.strftime('%B %d, %Y')}." }

  # The conversation types that are available. Defaults to ["Raif::Conversation"]
  # If you want to use custom conversation types that inherits from Raif::Conversation, you can add them here.
  # config.conversation_types += ["Raif::MyConversation"]

  # The controller class for conversations. Defaults to "Raif::ConversationsController"
  # If you want to use a custom controller that inherits from Raif::ConversationsController, you can set it here.
  # config.conversations_controller = "Raif::ConversationsController"

  # The controller class for conversation entries. Defaults to "Raif::ConversationEntriesController"
  # If you want to use a custom controller that inherits from Raif::ConversationEntriesController, you can set it here.
  # config.conversation_entries_controller = "Raif::ConversationEntriesController"

  # The default maximum number of conversation entries to include in LLM messages. Defaults to 50.
  # Set to nil to include all entries. Each conversation can override this with its own llm_messages_max_length attribute.
  # config.conversation_llm_messages_max_length_default = 50

  # The maximum number of times a Raif::ConversationEntry will re-prompt the model after it returns invalid
  # developer-managed tool calls. On each retry, a synthetic user-role feedback message describing the
  # validation failure (tool name, raw arguments, schema, available tools) is appended to that attempt's
  # LLM request. Defaults to 2 (up to 3 ModelCompletion rows per entry: initial + 2 retries).
  # config.conversation_entry_max_retries = 2

  # The method to call to get the current user. Defaults to :current_user
  # config.current_user_method = :current_user

  # The agent types that are available. Defaults to Set.new(["Raif::Agents::NativeToolCallingAgent"])
  # If you want to use custom agent types that inherits from Raif::Agent, you can add them here.
  # config.agent_types += ["MyAgent"]

  # The superclass for Raif models. Defaults to "ApplicationRecord"
  # config.model_superclass = "ApplicationRecord"

  # The user tool types that are available. Defaults to []
  # config.user_tool_types = []

  # The chunk size threshold for streaming updates. Defaults to 25.
  # config.streaming_update_chunk_size_threshold = 25

  # Raif model keys whose streaming path is unreliable. When a caller passes
  # a block to Raif::Llm#chat for one of these models, Raif transparently
  # falls back to the non-streaming path. Each entry may be a String, Symbol,
  # or Regexp matched against the model key. Defaults to
  # [/\Abedrock_gpt_oss_/] (Bedrock Converse streaming corrupts tool_use
  # deltas for gpt-oss). Set to [] to disable the workaround.
  # config.streaming_unsupported_model_keys = [/\Abedrock_gpt_oss_/]

  # Whether LLM API requests are enabled. Defaults to true.
  # Use this to globally disable requests to LLM APIs.
  # config.llm_api_requests_enabled = true

  # Optional lambda called with llm:/source: keyword args at the start of
  # Raif::Llm#chat, before the Raif::ModelCompletion is created or any provider
  # API call is made (and before the llm_api_requests_enabled guard). Raise
  # from it to veto the request; return values are ignored. Useful for
  # enforcing per-account usage limits. Does not apply to embedding generation
  # or batch API submissions. Defaults to nil (all requests allowed).
  # config.model_completion_authorizer = ->(llm:, source:) {
  #   account = source.account if source.respond_to?(:account)
  #   raise MyApp::UsageLimitExceededError if account && !account.within_llm_usage_limits?
  # }

  # Whether Raif creates a durable Raif::InferenceCostEvent for each model
  # completion that reaches a terminal state (completed or failed). Cost
  # events are slim rows that survive deletion of the completion, so cost
  # reporting keeps working after old completions are culled. Defaults to true.
  # config.inference_cost_events_enabled = true

  # Optional callable receiving a model_completion: keyword argument and
  # returning a hash merged into the Raif::InferenceCostEvent's metadata when
  # the event is created/updated. Use this to attach host application context
  # (e.g. account or workflow ids) without monkeypatching. Defaults to nil.
  # config.inference_cost_event_metadata = ->(model_completion:) {
  #   { account_id: model_completion.source.try(:account_id) }
  # }

  # Archival of old Raif::ModelCompletion and Raif::Task rows. Disabled by
  # default: with archive_enabled false and no archive_storage adapter
  # configured, Raif never deletes anything. Enabling requires
  # archive_enabled, archive_storage and at least one retention period, plus
  # scheduling the matching job (e.g. nightly) and
  # Raif::RepairInferenceCostEventsJob (e.g. daily). Preview what a run
  # would do, before enabling, with
  # Raif::ArchiveModelCompletionsJob.dry_run or
  # Raif::ArchiveTasksJob.dry_run.
  # Full guide: https://docs.raif.ai/learn_more/archiving
  # config.archive_enabled = false

  # Storage adapter used by the archive job. Raif ships
  # Raif::ArchiveStorage::FileSystem (local disk); production hosts
  # typically supply their own, commonly S3-backed. The adapter contract is
  # documented in the archiving guide linked above.
  #
  # Archives contain full prompts and responses, so the target must be
  # private, encrypted, and access-controlled at least as strictly as your
  # application data. Apply that policy, and any lifecycle rules, to whole
  # prefixes rather than deriving it from raif_archives rows: a crashed run
  # can leave an uploaded object that no row references.
  # config.archive_storage = Raif::ArchiveStorage::FileSystem.new(root: Rails.root.join("storage", "raif-archives"))

  # Partition archives by a column on the archived resource (e.g. a
  # host-added account_id on raif_model_completions), which is what lets
  # Raif::Archive.purge_partition! erase one tenant's archived data - its
  # objects and audit rows, not its live records. nil (the default) keeps
  # unpartitioned behavior, and enabling this later does not retrofit
  # archives created without it.
  #
  # The column's value MUST be immutable for a record's lifetime (e.g. pair
  # a NOT NULL column with attr_readonly and
  # config.active_record.raise_on_assign_to_attr_readonly): a record that
  # changes partitions mid-archival can leave a copy under its old prefix
  # that the new partition's purge can never find.
  # config.archive_partition_column = nil

  # With a partition column set, a record whose partition value is NULL (or
  # normalizes to blank) fails closed by default: it is never archived, so
  # a later tenant purge cannot miss records that lost their attribution.
  # Hosts with intentionally global/unowned records may explicitly set
  # Raif::ArchivePartition::UNGROUPED to archive them under a reserved
  # "_ungrouped" storage segment that purge_partition! never touches.
  # config.archive_partition_fallback = nil

  # How long model completions are retained before being archived and
  # deleted. Applies to completed/failed completions AND to nonterminal
  # completions older than the cutoff; the latter have no cost event, so no
  # per-record link back to their archive survives. nil (the default)
  # disables model completion culling even when archive_enabled is true.
  # Must be at least 1 month.
  # config.model_completion_retention_period = 6.months

  # How long Raif::Task rows are retained before Raif::ArchiveTasksJob
  # archives and deletes them. Applies to completed/failed tasks AND to
  # nonterminal tasks older than the cutoff. nil (the default) disables task
  # culling even when archive_enabled is true. Must be at least 1 month.
  #
  # A task is never culled while its Raif::ModelCompletion row survives, so
  # a value below model_completion_retention_period does not cull tasks any
  # sooner - it just lets the completion's window govern both. Tasks
  # referenced by a prompt studio batch run are retained indefinitely.
  # config.task_retention_period = 6.months

  # Timeout settings for LLM API requests (in seconds). All default to nil (use Faraday defaults).
  # config.request_open_timeout = nil  # Time to wait for a connection to be opened
  # config.request_read_timeout = nil  # Time to wait for data to be read
  # config.request_write_timeout = nil # Time to wait for data to be written

  # The default LLM model to use for LLM-as-judge evaluations.
  # If not set, falls back to default_llm_model_key, so the model being evaluated grades its own
  # output and comparing two models switches the judge along with the subject. Set this to hold the
  # judge fixed, ideally to a model from outside the family under test.
  # config.evals_default_llm_judge_model_key = ENV["RAIF_EVALS_DEFAULT_LLM_JUDGE_MODEL_KEY"].presence

  # Whether to output verbose information during evaluation runs. Defaults to false.
  # When true, provides more detailed output including individual test results.
  # config.evals_verbose_output = false

  # How many eval executions run at once. An eval run is almost entirely spent waiting on
  # provider responses, so this is the wall clock. Defaults to 1 (serial); `raif evals
  # --concurrency N` overrides it per run. Raising it requires a database connection pool
  # larger than the concurrency (see `pool:` in config/database.yml) and enough provider rate
  # limit to absorb the requests.
  # config.evals_concurrency = 1
end
