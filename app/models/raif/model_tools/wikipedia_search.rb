# frozen_string_literal: true

class Raif::ModelTools::WikipediaSearch < Raif::ModelTool
  tool_arguments_schema do
    string "query", description: "The query to search Wikipedia for"
  end

  example_model_invocation do
    {
      "name" => tool_name,
      "arguments" => { "query": "Jimmy Buffett" }
    }
  end

  tool_description do
    "Search Wikipedia for information"
  end

  class << self
    def format_result_for_llm(invocation)
      return "No results found" unless invocation.result.present?

      JSON.pretty_generate(invocation.result)
    end

    def triggers_immediate_follow_up_turn?(_invocation)
      true
    end

    def process_invocation(tool_invocation)
      query = tool_invocation.tool_arguments["query"]

      conn = Faraday.new(url: "https://en.wikipedia.org/w/api.php")

      response = conn.get do |req|
        req.params["action"] = "query"
        req.params["format"] = "json"
        req.params["list"] = "search"
        req.params["srsearch"] = query
        req.params["srlimit"] = 5 # Limit to 5 results
        req.params["srprop"] = "snippet"
      end

      if response.success?
        results = JSON.parse(response.body)
        search_results = results.dig("query", "search") || []

        # Store the results in the tool_invocation
        tool_invocation.update!(
          result: {
            results: search_results.map do |result|
              {
                title: result["title"],
                snippet: result["snippet"],
                page_id: result["pageid"],
                url: "https://en.wikipedia.org/wiki/#{result["title"].gsub(" ", "_")}"
              }
            end
          }
        )
      else
        tool_invocation.update!(
          result: {
            error: "Failed to fetch results from Wikipedia API: #{response.status} #{response.reason_phrase}"
          }
        )
      end

      tool_invocation.result
    end
  end

end
