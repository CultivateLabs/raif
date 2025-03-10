# frozen_string_literal: true

class Raif::ModelResponse
  attr_accessor :completion_tokens,
    :prompt_tokens,
    :raw_response,
    :response_format,
    :total_tokens

  def initialize(raw_response:, response_format: :text, completion_tokens:, prompt_tokens:, total_tokens:)
    unless Raif::Llm.valid_response_formats.include?(response_format.to_sym)
      raise ArgumentError,
        "Raif::ModelResponse#initialize - Invalid response format: #{response_format}. Must be one of: #{Raif::Llm.valid_response_formats.join(", ")}"
    end

    @raw_response = raw_response
    @response_format = response_format
    @completion_tokens = completion_tokens
    @prompt_tokens = prompt_tokens
    @total_tokens = total_tokens
  end

  def parsed_response
    @parsed_response ||= if response_format == :json
      json = raw_response.gsub("```json", "").gsub("```", "")
      JSON.parse(json)
    elsif response_format == :html
      html = raw_response.strip.gsub("```html", "").chomp("```")
      clean_html_fragment(html)
    else
      raw_response.strip
    end
  end

  def clean_html_fragment(html)
    fragment = Nokogiri::HTML.fragment(html)

    fragment.traverse do |node|
      if node.text? && node.text.strip.empty?
        node.remove
      end
    end

    ActionController::Base.helpers.sanitize(fragment.to_html).strip
  end
end
