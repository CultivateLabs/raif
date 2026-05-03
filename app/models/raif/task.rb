# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_tasks
#
#  id                     :bigint           not null, primary key
#  available_model_tools  :jsonb            not null
#  completed_at           :datetime
#  creator_type           :string
#  failed_at              :datetime
#  llm_model_key          :string           not null
#  prompt                 :text
#  prompt_studio_run      :boolean          default(FALSE), not null
#  raw_response           :text
#  requested_language_key :string
#  response_format        :integer          default("text"), not null
#  run_with               :jsonb
#  source_type            :string
#  started_at             :datetime
#  system_prompt          :text
#  type                   :string           not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  creator_id             :bigint
#  source_id              :bigint
#
# Indexes
#
#  index_raif_tasks_on_completed_at           (completed_at)
#  index_raif_tasks_on_created_at             (created_at)
#  index_raif_tasks_on_creator                (creator_type,creator_id)
#  index_raif_tasks_on_failed_at              (failed_at)
#  index_raif_tasks_on_source                 (source_type,source_id)
#  index_raif_tasks_on_started_at             (started_at)
#  index_raif_tasks_on_type                   (type)
#  index_raif_tasks_on_type_and_completed_at  (type,completed_at)
#  index_raif_tasks_on_type_and_failed_at     (type,failed_at)
#  index_raif_tasks_on_type_and_started_at    (type,started_at)
#
module Raif
  class Task < Raif::ApplicationRecord
    prepend Raif::Concerns::HasPromptTemplates

    include Raif::Concerns::HasLlm
    include Raif::Concerns::HasRequestedLanguage
    include Raif::Concerns::HasAvailableModelTools
    include Raif::Concerns::HasRuntimeDuration
    include Raif::Concerns::InvokesModelTools
    include Raif::Concerns::LlmResponseParsing
    include Raif::Concerns::LlmTemperature
    include Raif::Concerns::LlmPromptCaching
    include Raif::Concerns::JsonSchemaDefinition
    include Raif::Concerns::RunWith

    llm_temperature 0.7

    belongs_to :creator, polymorphic: true, optional: true
    belongs_to :source, polymorphic: true, optional: true

    validates :creator, presence: true, unless: -> { Raif.config.task_creator_optional }

    has_one :raif_model_completion, as: :source, dependent: :destroy, class_name: "Raif::ModelCompletion"

    boolean_timestamp :started_at
    boolean_timestamp :completed_at
    boolean_timestamp :failed_at

    normalizes :prompt, :system_prompt, with: ->(text){ text&.strip }

    scope :completed, -> { where.not(completed_at: nil) }
    scope :failed, -> { where.not(failed_at: nil) }
    scope :in_progress, -> { where.not(started_at: nil).where(completed_at: nil, failed_at: nil) }
    scope :pending, -> { where(started_at: nil, completed_at: nil, failed_at: nil) }

    attr_accessor :files, :images

    after_initialize -> { self.available_model_tools ||= [] }
    after_initialize -> { self.run_with ||= {} }

    def status
      if completed_at?
        :completed
      elsif failed_at?
        :failed
      elsif started_at?
        :in_progress
      else
        :pending
      end
    end

    # The primary interface for running a task. It will hit the LLM with the task's prompt and system prompt and return a Raif::Task object.
    # It will also create a new Raif::ModelCompletion record.
    #
    # @param creator [Object, nil] The creator of the task (polymorphic association), optional
    # @param available_model_tools [Array<Class>] Optional array of model tool classes that will be provided to the LLM for it to invoke.
    # @param llm_model_key [Symbol, String] Optional key for the LLM model to use. If blank, Raif.config.default_llm_model_key will be used.
    # @param images [Array] Optional array of Raif::ModelImageInput objects to include with the prompt.
    # @param files [Array] Optional array of Raif::ModelFileInput objects to include with the prompt.
    # @param args [Hash] Additional arguments to pass to the instance of the task that is created.
    # @return [Raif::Task, nil] The task instance that was created and run.
    def self.run(creator: nil, available_model_tools: [], llm_model_key: nil, images: [], files: [], **args, &block)
      task = new(
        creator: creator,
        llm_model_key: llm_model_key,
        available_model_tools: available_model_tools,
        started_at: Time.current,
        images: images,
        files: files,
        **args
      )

      task.save!
      task.run(&block)
      task
    rescue StandardError => e
      task&.failed!

      logger.error e.message
      logger.error e.backtrace.join("\n")

      if defined?(Airbrake)
        notice = Airbrake.build_notice(e)
        notice[:context][:component] = "raif_task"
        notice[:context][:action] = name

        Airbrake.notify(notice)
      end

      task
    end

    def run(skip_prompt_population: false, &block)
      update_columns(started_at: Time.current) if started_at.nil?

      populate_prompts unless skip_prompt_population

      streaming_block = if block_given?
        proc do |model_completion, delta, sse_event|
          update_columns(raw_response: model_completion.raw_response, updated_at: Time.current)
          block.call(model_completion, delta, sse_event)
        end
      end

      mc = llm.chat(
        messages: messages,
        source: self,
        system_prompt: system_prompt,
        response_format: response_format.to_sym,
        available_model_tools: available_model_tools,
        temperature: self.class.temperature,
        anthropic_prompt_caching_enabled: self.class.anthropic_prompt_caching_enabled,
        bedrock_prompt_caching_enabled: self.class.bedrock_prompt_caching_enabled,
        &streaming_block
      )

      process_completion!(mc)
    end

    def re_run(&block)
      update_columns(started_at: Time.current)
      run(skip_prompt_population: true, &block)
    end

    # Wires a (possibly batch-resolved) Raif::ModelCompletion back into this task:
    # links it as the task's raif_model_completion, mirrors raw_response onto the
    # task, processes any tool calls the model made, and transitions the task to
    # completed. Called by both the synchronous #run path and the batch
    # completion handler after the provider's per-entry result has been applied.
    #
    # @param model_completion [Raif::ModelCompletion]
    # @return [self]
    def process_completion!(model_completion)
      self.raif_model_completion = model_completion.becomes(Raif::ModelCompletion)

      update(raw_response: raif_model_completion.raw_response)

      process_model_tool_invocations
      completed!
      self
    end

    # Builds a Raif::Task and a pending Raif::ModelCompletion attached to the
    # given Raif::ModelCompletionBatch, without performing the LLM request. The
    # provider's batch-submission code reads the pending completion's request
    # fields when constructing its per-entry batch payload.
    #
    # The task is persisted with started_at: nil (state :pending). The pending
    # ModelCompletion has raif_model_completion_batch_id pointing at the batch
    # and provider_request_id set to the value used as the provider's custom_id
    # in the batch payload.
    #
    # @param batch [Raif::ModelCompletionBatch]
    # @param custom_request_id [String, nil] the provider custom_id; defaults to "raif_task_<task.id>"
    # @return [Raif::Task]
    def self.build_for_batch(batch:, custom_request_id: nil, creator: nil, available_model_tools: [],
      llm_model_key: nil, images: [], files: [], **args)
      task = new(
        creator: creator,
        llm_model_key: llm_model_key,
        available_model_tools: available_model_tools,
        images: images,
        files: files,
        **args
      )

      task.save!
      task.prepare_for_batch!(batch: batch, custom_request_id: custom_request_id)
      task
    end

    # Populates this task's prompts (if not already populated) and creates the
    # pending Raif::ModelCompletion that will be sent through the batch. Safe to
    # call on a task whose prompts haven't been built yet.
    #
    # @param batch [Raif::ModelCompletionBatch]
    # @param custom_request_id [String, nil]
    # @return [Raif::ModelCompletion]
    def prepare_for_batch!(batch:, custom_request_id: nil)
      send(:populate_prompts) if prompt.blank? && system_prompt.blank?
      save! if changed?

      effective_custom_request_id = custom_request_id.presence || "raif_task_#{id}"

      mc = llm.build_pending_model_completion(
        messages: messages,
        source: self,
        system_prompt: system_prompt,
        response_format: response_format.to_sym,
        available_model_tools: available_model_tools,
        temperature: self.class.temperature,
        anthropic_prompt_caching_enabled: self.class.anthropic_prompt_caching_enabled,
        bedrock_prompt_caching_enabled: self.class.bedrock_prompt_caching_enabled,
        raif_model_completion_batch: batch,
        provider_request_id: effective_custom_request_id
      )

      self.raif_model_completion = mc
      mc
    end

    def messages
      [{ "role" => "user", "content" => message_content }]
    end

    # Returns the LLM prompt for the task.
    #
    # @param creator [Object, nil] The creator of the task (polymorphic association), optional
    # @param args [Hash] Additional arguments to pass to the instance of the task that is created.
    # @return [String] The LLM prompt for the task.
    def self.prompt(creator: nil, **args)
      new(creator:, **args).build_prompt
    end

    # Returns the LLM system prompt for the task.
    #
    # @param creator [Object, nil] The creator of the task (polymorphic association), optional
    # @param args [Hash] Additional arguments to pass to the instance of the task that is created.
    # @return [String] The LLM system prompt for the task.
    def self.system_prompt(creator: nil, **args)
      new(creator:, **args).build_system_prompt
    end

    def self.json_response_schema(&block)
      if block_given?
        json_schema_definition(:json_response, &block)
      elsif schema_defined?(:json_response)
        schema_for(:json_response)
      end
    end

    # Instance method to get the JSON response schema
    # For instance-dependent schemas, builds the schema with this instance as context
    # For class-level schemas, returns the class-level schema
    def json_response_schema
      schema_for_instance(:json_response)
    end

    # Returns additional attributes to assign when creating tasks in Prompt Studio
    # (reruns, batch runs, and judge tasks). Override in your ApplicationTask or
    # task subclass to include app-specific attributes.
    #
    # @return [Hash] additional attributes to assign to the new task
    def prompt_studio_task_attributes
      {}
    end

    def build_prompt
      raise NotImplementedError, "Raif::Task subclasses must implement #build_prompt"
    end

    def build_system_prompt
      sp = Raif.config.task_system_prompt_intro
      sp = sp.call(self) if sp.respond_to?(:call)
      sp += system_prompt_language_preference if requested_language_key.present?
      sp
    end

  private

    def message_content
      # If there are no images or files, just return the message content can just be a string with the prompt
      return prompt if images.blank? && files.blank?

      content = [{ "type" => "text", "text" => prompt }]

      images.each do |image|
        raise Raif::Errors::InvalidModelImageInputError,
          "Images must be a Raif::ModelImageInput: #{image.inspect}" unless image.is_a?(Raif::ModelImageInput)

        content << image
      end

      files.each do |file|
        raise Raif::Errors::InvalidFileInputError,
          "Files must be a Raif::ModelFileInput: #{file.inspect}" unless file.is_a?(Raif::ModelFileInput)

        content << file
      end

      content
    end

    def populate_prompts
      self.requested_language_key ||= creator&.preferred_language_key if creator&.respond_to?(:preferred_language_key)
      self.prompt = build_prompt
      self.system_prompt = build_system_prompt
    end

    def process_model_tool_invocations
      return unless raif_model_completion&.response_tool_calls.present?

      raif_model_completion.response_tool_calls.each do |tool_call|
        tool_klass = available_model_tools_map[tool_call["name"]]
        next unless tool_klass

        tool_klass.invoke_tool(provider_tool_call_id: tool_call["provider_tool_call_id"], tool_arguments: tool_call["arguments"], source: self)
      end
    end

  end
end
