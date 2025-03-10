# frozen_string_literal: true

class Raif::ModelResponse < Raif::ApplicationRecord
  belongs_to :source, polymorphic: true, optional: true

  enum :response_format, Raif::Llm.valid_response_formats, prefix: true

  validates :response_format, presence: true, inclusion: { in: response_formats.keys }
  validates :llm_model_name, presence: true, inclusion: { in: Raif.available_llm_keys.map(&:to_s) }

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
