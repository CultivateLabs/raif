# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_agents
#
#  id                     :bigint           not null, primary key
#  available_model_tools  :jsonb            not null
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
  module Agents
    class ReActAgent < Raif::Agent
      validates :available_model_tools, length: {
        minimum: 1,
        message: ->(_object, _data) {
          I18n.t("raif.agents.re_act_agent.errors.available_model_tools.too_short")
        }
      }

      def build_system_prompt
        <<~PROMPT.strip
          You are an intelligent assistant that follows the ReAct (Reasoning + Acting) framework to complete tasks step by step using tool calls.

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

    private

      def process_iteration_model_completion(model_completion)
        agent_step = Raif::Agents::ReActStep.new(model_response_text: model_completion.raw_response)

        # Add the thought to conversation history
        if agent_step.thought
          add_conversation_history_entry({ role: "assistant", content: "<thought>#{agent_step.thought}</thought>" })
        end

        # If there's an answer, we're done
        if agent_step.answer
          self.final_answer = agent_step.answer
          add_conversation_history_entry({ role: "assistant", content: "<answer>#{agent_step.answer}</answer>" })
          return
        end

        # If there's an action, execute it
        process_action(agent_step.action) if agent_step.action
      end

      def process_action(action)
        add_conversation_history_entry({ role: "assistant", content: "<action>#{action}</action>" })

        # The action should always be a JSON object with "tool" and "arguments" keys
        parsed_action = begin
          JSON.parse(action)
        rescue JSON::ParserError => e
          add_conversation_history_entry({
            role: "assistant",
            content: "<observation>Error parsing action JSON: #{e.message}</observation>"
          })

          nil
        end

        return if parsed_action.blank?

        unless parsed_action["tool"] && parsed_action["arguments"]
          add_conversation_history_entry({
            role: "assistant",
            content: "<observation>Error: Invalid action specified. Please provide a valid action, formatted as a JSON object with 'tool' and 'arguments' keys.</observation>" # rubocop:disable Layout/LineLength
          })
          return
        end

        tool_name = parsed_action["tool"]
        tool_arguments = parsed_action["arguments"]
        tool_klass = available_model_tools_map[tool_name]

        # The model tried to use a tool that doesn't exist
        unless tool_klass
          add_conversation_history_entry({
            role: "assistant",
            content: "<observation>Error: Tool '#{tool_name}' not found. Available tools: #{available_model_tools_map.keys.join(", ")}</observation>"
          })
          return
        end

        unless JSON::Validator.validate(tool_klass.tool_arguments_schema, tool_arguments)
          add_conversation_history_entry({
            role: "assistant",
            content: "<observation>Error: Invalid tool arguments. Please provide valid arguments for the tool '#{tool_name}'. Tool arguments schema: #{tool_klass.tool_arguments_schema.to_json}</observation>" # rubocop:disable Layout/LineLength
          })
          return
        end

        tool_invocation = tool_klass.invoke_tool(tool_arguments: tool_arguments, source: self)
        observation = tool_klass.observation_for_invocation(tool_invocation)

        # Add the tool invocation to conversation history
        add_conversation_history_entry({
          role: "assistant",
          content: "<observation>#{observation}</observation>"
        })
      end

    end
  end
end
