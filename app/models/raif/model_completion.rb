# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_model_completions
#
#  id                             :bigint           not null, primary key
#  available_model_tools          :jsonb            not null
#  cache_creation_input_tokens    :integer
#  cache_read_input_tokens        :integer
#  citations                      :jsonb
#  completed_at                   :datetime
#  completion_tokens              :integer
#  failed_at                      :datetime
#  failure_error                  :string
#  failure_reason                 :text
#  failure_response_body          :text
#  failure_response_status        :integer
#  llm_model_key                  :string           not null
#  max_completion_tokens          :integer
#  messages                       :jsonb            not null
#  model_api_name                 :string           not null
#  output_token_cost              :decimal(10, 6)
#  prompt_token_cost              :decimal(10, 6)
#  prompt_tokens                  :integer
#  raw_response                   :text
#  response_array                 :jsonb
#  response_finish_reason         :string
#  response_format                :integer          default("text"), not null
#  response_format_parameter      :string
#  response_tool_calls            :jsonb
#  retry_count                    :integer          default(0), not null
#  source_type                    :string
#  started_at                     :datetime
#  stream_response                :boolean          default(FALSE), not null
#  system_prompt                  :text
#  temperature                    :decimal(5, 3)
#  tool_choice                    :string
#  total_cost                     :decimal(10, 6)
#  total_tokens                   :integer
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  batch_custom_id                :string
#  raif_model_completion_batch_id :bigint
#  response_id                    :string
#  source_id                      :bigint
#
# Indexes
#
#  index_raif_model_completions_on_batch_custom_id                 (batch_custom_id)
#  index_raif_model_completions_on_batch_id_and_custom_id          (raif_model_completion_batch_id,batch_custom_id) UNIQUE WHERE (raif_model_completion_batch_id IS NOT NULL)
#  index_raif_model_completions_on_completed_at                    (completed_at)
#  index_raif_model_completions_on_created_at                      (created_at)
#  index_raif_model_completions_on_failed_at                       (failed_at)
#  index_raif_model_completions_on_raif_model_completion_batch_id  (raif_model_completion_batch_id)
#  index_raif_model_completions_on_source                          (source_type,source_id)
#  index_raif_model_completions_on_started_at                      (started_at)
#
# Foreign Keys
#
#  fk_rails_...  (raif_model_completion_batch_id => raif_model_completion_batches.id)
#
class Raif::ModelCompletion < Raif::ApplicationRecord
  include Raif::Concerns::LlmResponseParsing
  include Raif::Concerns::HasAvailableModelTools
  include Raif::Concerns::HasRuntimeDuration
  include Raif::Concerns::ProviderManagedToolCalls
  include Raif::Concerns::BooleanTimestamp

  attr_accessor :anthropic_prompt_caching_enabled, :bedrock_prompt_caching_enabled

  boolean_timestamp :started_at
  boolean_timestamp :completed_at
  boolean_timestamp :failed_at

  belongs_to :source, polymorphic: true, optional: true
  belongs_to :raif_model_completion_batch,
    class_name: "Raif::ModelCompletionBatch",
    inverse_of: :raif_model_completions,
    optional: true

  validates :llm_model_key, presence: true, inclusion: { in: ->{ Raif.available_llm_keys.map(&:to_s) } }
  validates :model_api_name, presence: true

  scope :pending, -> { where(started_at: nil, completed_at: nil, failed_at: nil) }

  def pending?
    started_at.nil? && completed_at.nil? && failed_at.nil?
  end

  # Raw provider-reported finish/stop reasons that indicate the response was cut off
  # before completing - either at the maximum output token limit, or (on Anthropic
  # models) because the request exhausted the model's context window
  # (model_context_window_exceeded). The response (including any tool calls in it) is
  # incomplete and should not be trusted.
  #
  # Deliberately excluded: content-filter stops (e.g. OpenAI's "content_filter" /
  # incomplete_details.reason "content_filter"). Those responses are also cut short,
  # but the truncation-recovery guidance ("be more concise and retry") would be wrong
  # for them; their partial tool calls are still rejected by argument validation.
  TRUNCATED_FINISH_REASONS = %w[max_output_tokens length max_tokens MAX_TOKENS incomplete model_context_window_exceeded].freeze

  def truncated?
    TRUNCATED_FINISH_REASONS.include?(response_finish_reason)
  end

  # Scope to find completions that have response tool calls
  scope :with_response_tool_calls, -> { where_json_not_blank(:response_tool_calls) }

  delegate :json_response_schema, to: :source, allow_nil: true

  before_save :set_total_tokens
  before_save :calculate_costs

  after_initialize -> { self.messages ||= [] }
  after_initialize -> { self.available_model_tools ||= [] }
  after_initialize -> { self.response_array ||= [] }
  after_initialize -> { self.citations ||= [] }

  def json_response_schema
    source.json_response_schema if source&.respond_to?(:json_response_schema)
  end

  def set_total_tokens
    self.total_tokens ||= completion_tokens.present? && prompt_tokens.present? ? completion_tokens + prompt_tokens : nil
  end

  def calculate_costs
    # Each retry resends the same prompt, so the provider charges input tokens
    # for every attempt. Factor in retry_count to reflect actual billing.
    total_attempts = (retry_count || 0) + 1

    if prompt_tokens.present? && llm_config[:input_token_cost].present?
      self.prompt_token_cost = calculate_prompt_token_cost(total_attempts)
    end

    if completion_tokens.present? && llm_config[:output_token_cost].present?
      self.output_token_cost = llm_config[:output_token_cost] * completion_tokens
    end

    if prompt_token_cost.present? || output_token_cost.present?
      self.total_cost = (prompt_token_cost || 0) + (output_token_cost || 0)
    end

    apply_batch_inference_discount if raif_model_completion_batch_id.present?
  end

  # Maximum number of characters of an upstream HTTP body we persist on
  # failure. The body usually carries the provider's actual error reason
  # (e.g. OpenAI/Anthropic structured error JSON), which `failure_reason`
  # cannot fit in 255 chars. 4 KB is enough to capture realistic error
  # payloads without bloating storage.
  FAILURE_RESPONSE_BODY_MAX_CHARS = 4_000

  def record_failure!(exception)
    self.failed_at = Time.current
    self.failure_error = exception.class.name
    self.failure_reason = exception.message.truncate(255)
    # Always clear before re-populating so a second call with a different
    # exception kind doesn't leave stale response metadata attached.
    self.failure_response_status = nil
    self.failure_response_body = nil

    # Faraday errors carry the provider's HTTP status and response body —
    # the latter is where the actual provider-side error reason lives. Both
    # are nil when the failure happened before a response was received
    # (DNS/connection refused/timeout).
    if exception.is_a?(Faraday::Error)
      self.failure_response_status = exception.response_status
      body = exception.response_body
      self.failure_response_body = body.to_s.first(FAILURE_RESPONSE_BODY_MAX_CHARS) if body.present?
    end

    save!
  end

private

  def calculate_prompt_token_cost(total_attempts)
    input_cost = llm_config[:input_token_cost]
    llm_class = llm_config[:llm_class]
    cache_read_multiplier = llm_class&.cache_read_input_token_cost_multiplier
    cache_creation_multiplier = llm_class&.cache_creation_input_token_cost_multiplier
    cached_reads = cache_read_input_tokens.to_i
    cached_writes = cache_creation_input_tokens.to_i

    if cached_reads > 0 && cache_read_multiplier.present?
      cache_read_cost = input_cost * cache_read_multiplier

      if llm_class.prompt_tokens_include_cached_tokens?
        # OpenAI / Google / OpenRouter: cached tokens are a subset of prompt_tokens
        non_cached = prompt_tokens - cached_reads
        cost = (non_cached * input_cost) + (cached_reads * cache_read_cost)
      else
        # Anthropic / Bedrock: cached tokens are separate from prompt_tokens
        cost = (prompt_tokens * input_cost) + (cached_reads * cache_read_cost)
      end
    else
      cost = prompt_tokens * input_cost
    end

    # Cache creation surcharge (Anthropic / Bedrock)
    if cached_writes > 0 && cache_creation_multiplier.present?
      cost += cached_writes * input_cost * cache_creation_multiplier
    end

    cost * total_attempts
  end

  def llm_config
    @llm_config ||= Raif.llm_config(llm_model_key.to_sym)
  end

  # When this completion was resolved through a provider Batch API, apply the
  # provider's batch-tier multiplier (typically 0.5 for both Anthropic and
  # OpenAI today) to the per-token costs. Total recomputed from parts so it
  # tracks any rounding consistently.
  def apply_batch_inference_discount
    multiplier = llm_config[:llm_class]&.batch_inference_cost_multiplier
    return unless multiplier && multiplier != 1.0

    self.prompt_token_cost = ((prompt_token_cost || 0) * multiplier) if prompt_token_cost.present?
    self.output_token_cost = ((output_token_cost || 0) * multiplier) if output_token_cost.present?

    # Mirror calculate_costs's guard so a fresh batch completion (no tokens
    # recorded yet) doesn't get total_cost coerced from NULL to 0 -- otherwise
    # batch completions diverge from non-batch completions in the time
    # between persist and result-application.
    if prompt_token_cost.present? || output_token_cost.present?
      self.total_cost = (prompt_token_cost || 0) + (output_token_cost || 0)
    end
  end
end
