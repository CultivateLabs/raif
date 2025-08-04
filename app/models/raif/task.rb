# frozen_string_literal: true

module Raif
  class Task < Raif::ApplicationRecord
    include Raif::Concerns::HasLlm
    include Raif::Concerns::HasRequestedLanguage
    include Raif::Concerns::HasAvailableModelTools
    include Raif::Concerns::InvokesModelTools
    include Raif::Concerns::LlmResponseParsing
    include Raif::Concerns::LlmTemperature
    include Raif::Concerns::JsonSchemaDefinition
    include Raif::Concerns::TaskRunArgs

    llm_temperature 0.7

    belongs_to :creator, polymorphic: true

    has_one :raif_model_completion, as: :source, dependent: :destroy, class_name: "Raif::ModelCompletion"

    boolean_timestamp :started_at
    boolean_timestamp :completed_at
    boolean_timestamp :failed_at

    normalizes :prompt, :system_prompt, with: ->(text){ text&.strip }

    delegate :json_response_schema, to: :class

    scope :completed, -> { where.not(completed_at: nil) }
    scope :failed, -> { where.not(failed_at: nil) }
    scope :in_progress, -> { where.not(started_at: nil).where(completed_at: nil, failed_at: nil) }
    scope :pending, -> { where(started_at: nil, completed_at: nil, failed_at: nil) }

    attr_accessor :files, :images

    after_initialize -> { self.available_model_tools ||= [] }

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
    # @param creator [Object] The creator of the task (polymorphic association)
    # @param available_model_tools [Array<Class>] Optional array of model tool classes that will be provided to the LLM for it to invoke.
    # @param llm_model_key [Symbol, String] Optional key for the LLM model to use. If blank, Raif.config.default_llm_model_key will be used.
    # @param images [Array] Optional array of Raif::ModelImageInput objects to include with the prompt.
    # @param files [Array] Optional array of Raif::ModelFileInput objects to include with the prompt.
    # @param args [Hash] Additional arguments to pass to the instance of the task that is created.
    # @return [Raif::Task, nil] The task instance that was created and run.
    def self.run(creator:, available_model_tools: [], llm_model_key: nil, images: [], files: [], **args)
      task = new(
        creator: creator,
        llm_model_key: llm_model_key,
        available_model_tools: available_model_tools,
        started_at: Time.current,
        images: images,
        files: files,
        task_run_args: serialize_task_run_args(args),
        **args
      )

      task.save!
      task.run
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

    def run(skip_prompt_population: false)
      update_columns(started_at: Time.current) if started_at.nil?

      populate_prompts unless skip_prompt_population
      messages = [{ "role" => "user", "content" => message_content }]

      mc = llm.chat(
        messages: messages,
        source: self,
        system_prompt: system_prompt,
        response_format: response_format.to_sym,
        available_model_tools: available_model_tools,
        temperature: self.class.temperature
      )

      self.raif_model_completion = mc.becomes(Raif::ModelCompletion)

      update(raw_response: raif_model_completion.raw_response)

      process_model_tool_invocations
      completed!
      self
    end

    def re_run
      update_columns(started_at: Time.current)
      run(skip_prompt_population: true)
    end

    # Returns the LLM prompt for the task.
    #
    # @param creator [Object] The creator of the task (polymorphic association)
    # @param args [Hash] Additional arguments to pass to the instance of the task that is created.
    # @return [String] The LLM prompt for the task.
    def self.prompt(creator:, **args)
      new(creator:, **args).build_prompt
    end

    # Returns the LLM system prompt for the task.
    #
    # @param creator [Object] The creator of the task (polymorphic association)
    # @param args [Hash] Additional arguments to pass to the instance of the task that is created.
    # @return [String] The LLM system prompt for the task.
    def self.system_prompt(creator:, **args)
      new(creator:, **args).build_system_prompt
    end

    def self.json_response_schema(&block)
      if block_given?
        json_schema_definition(:json_response, &block)
      elsif schema_defined?(:json_response)
        schema_for(:json_response)
      end
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
      self.requested_language_key ||= creator.preferred_language_key if creator.respond_to?(:preferred_language_key)
      self.prompt = build_prompt
      self.system_prompt = build_system_prompt
    end

    def process_model_tool_invocations
      return unless response_format_json?
      return unless parsed_response.is_a?(Hash)
      return unless parsed_response["tools"].present? && parsed_response["tools"].is_a?(Array)

      parsed_response["tools"].each do |t|
        tool_klass = available_model_tools_map[t["name"]]
        next unless tool_klass

        tool_klass.invoke_tool(tool_arguments: t["arguments"], source: self)
      end
    end

  end
end
