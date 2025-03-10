# frozen_string_literal: true

class Raif::Utils::HtmlToMarkdownConverter
  def self.convert(html)
    ReverseMarkdown.convert(html, unknown_tags: :bypass)
  end
end
