# frozen_string_literal: true

class Raif::ModelTools::UserInputTool < Raif::ModelTool

  def self.example_model_invocation
    {
      "name": "get_user_input",
      "arguments": { "query": "Are you asking about New York state or city?" }
    }
  end

  def self.tool_description
    "Ask the user a question and wait for their response"
  end

  def self.tool_arguments_schema
    {
      query: {
        type: "string",
        description: "The question to ask the user"
      }
    }
  end

  def process_invocation(tool_invocation)
    query = tool_invocation.tool_arguments["query"]

    # Store the query in the tool_invocation result
    tool_invocation.update!(
      result: {
        query: query,
        status: "awaiting_user_input"
      }
    )

    # Return the result
    tool_invocation.result
  end

end
