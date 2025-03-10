# frozen_string_literal: true

class Raif::ModelTools::WikipediaSearchTool < Raif::ModelTool

  def self.example_model_invocation
    {
      "name": "wikipedia_search",
      "arguments": { "query": "Jimmy Buffett" }
    }
  end

  def self.tool_arguments_schema
    {
      query: {
        type: "string",
        description: "The query to search Wikipedia for"
      }
    }
  end

  def self.tool_description
    "Search Wikipedia for information"
  end

  def self.observation_for_invocation(tool_invocation)
    return "No results found" unless tool_invocation.result.present?

    JSON.pretty_generate(tool_invocation.result)
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
