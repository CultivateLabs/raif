# frozen_string_literal: true

class Raif::Agent

  attr_accessor :task, :available_model_tools, :creator, :llm_model_name, :max_iterations

  def initialize(task:, tools:, creator:, llm_model_name: nil, max_iterations: 10)
    @task = task
    @available_model_tools = tools
    @creator = creator
    @llm_model_name = llm_model_name
    @max_iterations = max_iterations
  end

  def run!
    agent_invocation = Raif::AgentInvocation.new(
      task: task,
      available_model_tools: available_model_tools,
      system_prompt: system_prompt,
      creator: creator,
      llm_model_name: llm_model_name,
      max_iterations: max_iterations
    )

    agent_invocation.run!
    agent_invocation
  end

  def system_prompt
    <<~PROMPT
      You are an intelligent assistant that follows the ReAct (Reasoning + Acting) framework to complete tasks step by step using tool calls.

      # Available Tools
      You have access to the following tools:
      #{available_model_tools.map(&:description_for_llm).join("\n---\n")}

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

      Remember: Your goal is to be helpful, accurate, and efficient in solving the user's request.
    PROMPT
  end
end
