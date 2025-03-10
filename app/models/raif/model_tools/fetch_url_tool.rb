# frozen_string_literal: true

class Raif::ModelTools::FetchUrlTool < Raif::ModelTool

  def self.example_model_invocation
    {
      "name": "fetch_url",
      "arguments": { "url": "https://en.wikipedia.org/wiki/NASA" }
    }
  end

  def self.tool_description
    "Fetch a URL and return the page content as markdown"
  end

  def self.tool_arguments_schema
    {
      url: {
        type: "string",
        description: "The URL to fetch"
      }
    }
  end

  def self.observation_for_invocation(tool_invocation)
    return "No results found" unless tool_invocation.result.present?

    <<~OBSERVATION
      Result Status: #{tool_invocation.result["status"]}
      Result Content:
      #{tool_invocation.result["content"]}
    OBSERVATION
  end

  def process_invocation(tool_invocation)
    url = tool_invocation.tool_arguments["url"]
    response = Faraday.get(url)

    readable_content = Raif::Utils::ReadableContentExtractor.new(response.body).extract_readable_content
    markdown_content = Raif::Utils::HtmlToMarkdownConverter.convert(readable_content)

    tool_invocation.update!(
      result: {
        status: response.status,
        content: markdown_content
      }
    )

    tool_invocation.result
  end

end
