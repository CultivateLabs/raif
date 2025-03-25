# frozen_string_literal: true

module Raif
  class AgentInvocation < ApplicationRecord
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

    validates :type, inclusion: { in: ->{ Raif.config.agent_invocation_types } }
    validates :task, presence: true
    validates :system_prompt, presence: true
    validates :max_iterations, presence: true, numericality: { greater_than: 0 }
    validates :available_model_tools, length: {
      minimum: 1,
      message: ->(_object, _data) {
        I18n.t("raif.agent_invocations.errors.available_model_tools.too_short")
      }
    }

    before_validation -> { self.system_prompt ||= build_system_prompt }, on: :create
    before_validation ->{ self.type ||= "Raif::AgentInvocation" }, on: :create

    attr_accessor :on_conversation_history_entry

    # Runs the agent and returns a Raif::AgentInvocation.
    # If a block is given, it will be called each time a new entry is added to the agent's conversation history.
    # The block will receive the Raif::AgentInvocation and the new entry as arguments:
    # agent_invocation = Raif::AgentInvocation.new(
    #   task: task,
    #   tools: [Raif::ModelTools::WikipediaSearch, Raif::ModelTools::FetchUrl],
    #   creator: creator
    # )
    #
    # agent_invocation.run! do |conversation_history_entry|
    #   Turbo::StreamsChannel.broadcast_append_to(
    #     :my_agent_channel,
    #     target: "agent-progress",
    #     partial: "my_partial_displaying_agent_progress",
    #     locals: { agent_invocation: agent_invocation, conversation_history_entry: conversation_history_entry }
    #   )
    # end
    #
    # The conversation_history_entry will be a hash with "role" and "content" keys:
    # { "role" => "assistant", "content" => "a message here" }
    #
    # @param block [Proc] Optional block to be called each time a new entry to the agent's conversation history is generated
    # @return [Raif::AgentInvocation] The agent invocation that was created and run
    def run!(&block)
      self.on_conversation_history_entry = block_given? ? block : nil
      self.started_at = Time.current
      save!

      add_conversation_history_entry({ role: "user", content: task })

      while iteration_count < max_iterations
        update_columns(iteration_count: iteration_count + 1)

        if iteration_count == 1
          logger.debug <<~DEBUG
            --------------------------------
            Starting Agent Run
            --------------------------------
            System Prompt:
            #{system_prompt}
          DEBUG
        end

        model_completion = llm.chat(
          messages: conversation_history,
          source: self,
          system_prompt: system_prompt,
          available_model_tools: available_model_tools
        )
        agent_step = Raif::AgentStep.new(model_response_text: model_completion.raw_response)
        logger.debug <<~DEBUG
          --------------------------------
          Agent iteration #{iteration_count}
          Messages:
          #{JSON.pretty_generate(conversation_history)}

          Response:
          #{model_completion.raw_response}
          --------------------------------
        DEBUG

        # Add the thought to conversation history
        if agent_step.thought
          add_conversation_history_entry({ role: "assistant", content: "<thought>#{agent_step.thought}</thought>" })
        end

        # If there's an answer, we're done
        if agent_step.answer
          self.final_answer = agent_step.answer
          add_conversation_history_entry({ role: "assistant", content: "<answer>#{agent_step.answer}</answer>" })
          break
        end

        # If there's an action, execute it
        next unless agent_step.action

        add_conversation_history_entry({ role: "assistant", content: "<action>#{agent_step.action}</action>" })

        if agent_step.parsed_action && agent_step.parsed_action["tool"] && agent_step.parsed_action["arguments"]
          process_action(agent_step.parsed_action)
        else
          # No action specified
          add_conversation_history_entry({
            role: "user",
            content: "<observation>Error: No valid action specified. Please provide a valid action, formatted as a JSON object with 'tool' and 'arguments' keys.</observation>" # rubocop:disable Layout/LineLength
          })
        end
      end

      completed!
      final_answer
    end

    def process_action(action)
      tool_name = action["tool"]
      tool_arguments = action["arguments"]

      # Find the tool class
      tool_klass = available_model_tools_map[tool_name]

      # The model tried to use a tool that doesn't exist
      unless tool_klass
        add_conversation_history_entry({
          role: "user",
          content: "<observation>Error: Tool '#{tool_name}' not found. Available tools: #{available_model_tools_map.keys.join(", ")}</observation>"
        })
        return
      end

      tool_invocation = tool_klass.invoke_tool(tool_arguments: tool_arguments, source: self)
      observation = tool_klass.observation_for_invocation(tool_invocation)

      # Add the tool invocation to conversation history
      add_conversation_history_entry({
        role: "user",
        content: "<observation>#{observation}</observation>"
      })
    end

    def add_conversation_history_entry(entry)
      entry_stringified = entry.stringify_keys
      conversation_history << entry_stringified
      on_conversation_history_entry.call(entry_stringified) if on_conversation_history_entry.present?
    end

    def system_prompt_intro
      Raif.config.agent_system_prompt_intro
    end

    def build_system_prompt
      <<~PROMPT
        #{system_prompt_intro}

        # Available Tools
        You have access to the following tools:
        #{available_model_tools_map.values.map(&:description_for_llm).join("\n---\n")}

        # Your Responses
        Your responses should follow this structure & format:
        <thought>Your step-by-step reasoning about what to do</thought>
        <action>JSON object with "tool" and "arguments" keys</action>
        <observation>Results from the tool, which will be provided to you</observation>
        ... (repeat Thought/Action/Observation as needed until the task is complete)
        <thought>Final reasoning based on all observations</thought>
        <answer>Your final response to the user</answer>

        # How to Use Tools
        When you need to use a tool:
        1. Identify which tool is appropriate for the task
        2. Format your tool call using JSON with the required arguments and place it in the <action> tag
        3. Here is an example: <action>{"tool": "tool_name", "arguments": {...}}</action>

        # Guidelines
        - Always think step by step
        - Use tools when appropriate, but don't use tools for tasks you can handle directly
        - Be concise in your reasoning but thorough in your analysis
        - If a tool returns an error, try to understand why and adjust your approach
        - If you're unsure about something, explain your uncertainty, but do not make things up
        - After each thought, make sure to also include an <action> or <answer>
        - Always provide a final answer that directly addresses the user's request

        Remember: Your goal is to be helpful, accurate, and efficient in solving the user's request.#{system_prompt_language_preference}
      PROMPT
    end

  end
end
