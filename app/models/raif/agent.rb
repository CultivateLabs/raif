# frozen_string_literal: true

module Raif
  class Agent < ApplicationRecord
    include Raif::Concerns::HasLlm
    include Raif::Concerns::HasRequestedLanguage
    include Raif::Concerns::HasAvailableModelTools
    include Raif::Concerns::InvokesModelTools

    belongs_to :creator, polymorphic: true

    has_many :raif_model_completions, as: :source, dependent: :destroy, class_name: "Raif::ModelCompletion"

    after_initialize -> { self.available_model_tools ||= [] }
    after_initialize -> { self.conversation_history ||= [] }

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

    # Runs the agent and returns a Raif::Agent.
    # If a block is given, it will be called each time a new entry is added to the agent's conversation history.
    # The block will receive the Raif::Agent and the new entry as arguments:
    # agent = Raif::Agent.new(
    #   task: task,
    #   tools: [Raif::ModelTools::WikipediaSearch, Raif::ModelTools::FetchUrl],
    #   creator: creator
    # )
    #
    # agent.run! do |conversation_history_entry|
    #   Turbo::StreamsChannel.broadcast_append_to(
    #     :my_agent_channel,
    #     target: "agent-progress",
    #     partial: "my_partial_displaying_agent_progress",
    #     locals: { agent: agent, conversation_history_entry: conversation_history_entry }
    #   )
    # end
    #
    # The conversation_history_entry will be a hash with "role" and "content" keys:
    # { "role" => "assistant", "content" => "a message here" }
    #
    # @param block [Proc] Optional block to be called each time a new entry to the agent's conversation history is generated
    # @return [Raif::Agent] The agent that was created and run
    def run!(&block)
      self.on_conversation_history_entry = block_given? ? block : nil
      self.started_at = Time.current
      save!

      logger.debug <<~DEBUG
        --------------------------------
        Starting Agent Run
        --------------------------------
        System Prompt:
        #{system_prompt}

        Task: #{task}
      DEBUG

      add_conversation_history_entry({ role: "user", content: task })

      while iteration_count < max_iterations
        update_columns(iteration_count: iteration_count + 1)

        model_completion = llm.chat(
          messages: conversation_history,
          source: self,
          system_prompt: system_prompt,
          available_model_tools: native_model_tools
        )

        logger.debug <<~DEBUG
          --------------------------------
          Agent iteration #{iteration_count}
          Messages:
          #{JSON.pretty_generate(conversation_history)}

          Response:
          #{model_completion.raw_response}
          --------------------------------
        DEBUG

        process_iteration_model_completion(model_completion)
        break if final_answer.present?
      end

      completed!
      final_answer
    rescue StandardError => e
      self.failed_at = Time.current
      self.failure_reason = e.message
      save!

      raise
    end

  private

    def populate_default_model_tools
      # no-op by default. Can be overridden by subclasses to add default model tools
    end

    def process_iteration_model_completion(model_completion)
      raise NotImplementedError, "#{self.class.name} must implement process_iteration_model_completion"
    end

    def native_model_tools
      # no-op by default
    end

    def add_conversation_history_entry(entry)
      entry_stringified = entry.stringify_keys
      conversation_history << entry_stringified
      save!
      on_conversation_history_entry.call(entry_stringified) if on_conversation_history_entry.present?
    end

    def build_system_prompt
      raise NotImplementedError, "Subclasses of Raif::Agent must implement build_system_prompt"
    end

  end
end
