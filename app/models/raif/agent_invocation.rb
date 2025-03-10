# frozen_string_literal: true

module Raif
  class AgentInvocation < ApplicationRecord
    include Raif::Concerns::HasLlm
    include Raif::Concerns::HasRequestedLanguage
    include Raif::Concerns::InvokesModelTools

    belongs_to :creator, polymorphic: true

    boolean_timestamp :started_at
    boolean_timestamp :completed_at
    boolean_timestamp :failed_at

    validates :task, presence: true
    validates :system_prompt, presence: true
    validates :max_iterations, presence: true, numericality: { greater_than: 0 }

    def run!
      self.started_at = Time.current
      save!

      conversation_history << { role: "user", content: task }

      while iteration_count < max_iterations
        update_columns(iteration_count: iteration_count + 1)

        if iteration_count == 1
          puts "\n\n"
          puts "--------------------------------"
          puts "Starting Agent Run"
          puts "--------------------------------"
          puts "System Prompt:"
          puts system_prompt
        end

        puts "\n"
        puts "--------------------------------"
        puts "Running Agent iteration #{iteration_count}"
        model_response = llm.chat(messages: conversation_history, system_prompt: system_prompt)
        puts "Messages:\n#{JSON.pretty_generate(conversation_history)}"
        puts "Response:\n#{model_response.raw_response}"
        puts "--------------------------------"
        puts "\n"

        # Extract thought, action, and answer from the model response
        thought = extract_thought(model_response.raw_response)
        action = extract_action(model_response.raw_response)
        answer = extract_answer(model_response.raw_response)

        # Add the thought to conversation history
        if thought
          conversation_history << { role: "assistant", content: "<thought>#{thought}</thought>" }
        end

        # If there's an answer, we're done
        if answer
          self.final_answer = answer
          conversation_history << { role: "assistant", content: "<answer>#{answer}</answer>" }
          break
        end

        # If there's an action, execute it
        if action && action["tool"] && action["arguments"]
          process_action(action)
        else
          # No action specified
          conversation_history << {
            role: "user",
            content: "<observation>Error: No valid action specified. Please provide a valid action with 'tool' and 'arguments' keys.</observation>"
          }
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
        conversation_history << {
          role: "user",
          content: "<observation>Error: Tool '#{tool_name}' not found. Available tools: #{available_model_tools.map(&:tool_name).join(", ")}</observation>" # rubocop:disable Layout/LineLength
        }
        return
      end

      tool_invocation = tool_klass.invoke_tool(tool_arguments: tool_arguments, source: self)
      observation = tool_klass.observation_for_invocation(tool_invocation)

      # Add the tool invocation to conversation history
      conversation_history << {
        role: "user",
        content: "<observation>#{observation}</observation>"
      }
    end

    def extract_thought(model_response_text)
      thought_match = model_response_text.match(%r{<thought>(.*?)</thought>}m)
      thought_match ? thought_match[1].strip : nil
    end

    def extract_action(model_response_text)
      action_match = model_response_text.match(%r{<action>(.*?)</action>}m)
      action_match ? JSON.parse(action_match[1].strip) : nil
    rescue JSON::ParserError
      nil
    end

    def extract_answer(model_response_text)
      answer_match = model_response_text.match(%r{<answer>(.*?)</answer>}m)
      answer_match ? answer_match[1].strip : nil
    end

  end
end
