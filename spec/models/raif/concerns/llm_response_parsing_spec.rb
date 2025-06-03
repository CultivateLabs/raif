# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Concerns::LlmResponseParsing do
  describe "llm_response_allowed_tags" do
    it "allows the specified tags" do
      expect(Raif::TestHtmlTask.allowed_tags).to eq(%w[p b i u s a])
    end

    it "strips tags that are not allowed" do
      task = Raif::TestHtmlTask.new(raw_response: "<div>Why is a pirate's favorite letter 'R'?</div><p>Because, if you think about it, <b style=\"color:red;\">R</b> is the only letter that makes sense.</p>") # rubocop:disable Layout/LineLength
      expect(task.parsed_response).to eq("Why is a pirate's favorite letter 'R'?<p>Because, if you think about it, <b style=\"color:red;\">R</b> is the only letter that makes sense.</p>") # rubocop:disable Layout/LineLength
    end
  end

  describe "llm_response_allowed_attributes" do
    it "allows the specified attributes" do
      expect(Raif::TestHtmlTask.allowed_attributes).to eq(%w[style href])
    end

    it "strips attributes that are not allowed" do
      task = Raif::TestHtmlTask.new(raw_response: "<p data-example='true'>Why is a pirate's favorite letter 'R'?</p><p>Because, if you think about it, <b style=\"color:red;\">R</b> is the only letter that makes sense.</p>") # rubocop:disable Layout/LineLength
      expect(task.parsed_response).to eq("<p>Why is a pirate's favorite letter 'R'?</p><p>Because, if you think about it, <b style=\"color:red;\">R</b> is the only letter that makes sense.</p>") # rubocop:disable Layout/LineLength
    end
  end

  describe "markdown link conversion" do
    context "with valid markdown links" do
      it "converts basic markdown links to HTML links" do
        task = Raif::TestHtmlTask.new(raw_response: "Check out [Google](https://google.com) for search.")
        expect(task.parsed_response).to eq('Check out <a href="https://google.com">Google</a> for search.')
      end

      it "converts multiple markdown links in the same content" do
        task = Raif::TestHtmlTask.new(raw_response: "Visit [Google](https://google.com) or [GitHub](https://github.com) for resources.")
        expect(task.parsed_response).to eq('Visit <a href="https://google.com">Google</a> or <a href="https://github.com">GitHub</a> for resources.')
      end

      it "converts markdown links within HTML content" do
        task = Raif::TestHtmlTask.new(raw_response: "<p>Visit [Google](https://google.com) for search.</p>")
        expect(task.parsed_response).to eq('<p>Visit <a href="https://google.com">Google</a> for search.</p>')
      end

      it "handles relative URLs" do
        task = Raif::TestHtmlTask.new(raw_response: "Go to [home page](/home) or [about page](../about).")
        expect(task.parsed_response).to eq('Go to <a href="/home">home page</a> or <a href="../about">about page</a>.')
      end
    end

    context "with dangerous URLs" do
      it "sanitizes javascript: URLs" do
        task = Raif::TestHtmlTask.new(raw_response: "Click [here](javascript:alert('xss')) for fun.")
        parsed = task.parsed_response
        # The link should be converted but the javascript: protocol should be removed by the sanitizer
        expect(parsed).not_to include("javascript:")
        expect(parsed).to include("here") # Text should remain
      end

      it "sanitizes data: URLs with scripts" do
        task = Raif::TestHtmlTask.new(raw_response: "Click [here](data:text/html,<script>alert('xss')</script>) for fun.")
        parsed = task.parsed_response
        expect(parsed).not_to include("data:")
        expect(parsed).to include("here")
      end

      it "sanitizes vbscript: URLs" do
        task = Raif::TestHtmlTask.new(raw_response: "Click [here](vbscript:alert('xss')) for fun.")
        parsed = task.parsed_response
        expect(parsed).not_to include("vbscript:")
        expect(parsed).to include("here")
      end

      it "allows safe protocols like mailto:" do
        task = Raif::TestHtmlTask.new(raw_response: "Email me at [contact](mailto:test@example.com).")
        parsed = task.parsed_response
        expect(parsed).to include('href="mailto:test@example.com"')
        expect(parsed).to include("contact")
      end
    end

    context "with edge cases" do
      it "handles markdown links with parentheses in the text" do
        task = Raif::TestHtmlTask.new(raw_response: "Check [Example (test)](https://example.com) site.")
        expect(task.parsed_response).to eq('Check <a href="https://example.com">Example (test)</a> site.')
      end

      it "handles markdown links with nested parentheses in the text" do
        task = Raif::TestHtmlTask.new(raw_response: "Check [Example ((test))](https://example.com) site.")
        expect(task.parsed_response).to eq('Check <a href="https://example.com">Example ((test))</a> site.')
      end

      it "handles markdown links with multiple parentheses in the text" do
        task = Raif::TestHtmlTask.new(raw_response: "Check [Example (test) (here)](https://example.com) site.")
        expect(task.parsed_response).to eq('Check <a href="https://example.com">Example (test) (here)</a> site.')
      end

      it "handles empty link text" do
        task = Raif::TestHtmlTask.new(raw_response: "Click [](https://example.com) to visit.")
        expect(task.parsed_response).to eq('Click <a href="https://example.com"></a> to visit.')
      end

      it "doesn't convert invalid markdown link syntax" do
        task = Raif::TestHtmlTask.new(raw_response: "This is not a link [missing closing paren](https://example.com and this [has no url].")
        expect(task.parsed_response).to eq("This is not a link [missing closing paren](https://example.com and this [has no url].")
      end

      it "handles content with no markdown links" do
        task = Raif::TestHtmlTask.new(raw_response: "<p>Just some regular HTML content.</p>")
        expect(task.parsed_response).to eq("<p>Just some regular HTML content.</p>")
      end
    end

    context "with HTML code blocks" do
      it "converts markdown links after stripping HTML code block markers" do
        task = Raif::TestHtmlTask.new(raw_response: "```html\n<p>Visit [Google](https://google.com)</p>\n```")
        expect(task.parsed_response).to eq('<p>Visit <a href="https://google.com">Google</a></p>')
      end
    end

    context "with tracking parameters" do
      it "strips UTM parameters from URLs" do
        task = Raif::TestHtmlTask.new(raw_response: "Check out [Google](https://google.com?utm_source=email&utm_medium=newsletter&utm_campaign=spring) for search.") # rubocop:disable Layout/LineLength
        expect(task.parsed_response).to eq('Check out <a href="https://google.com">Google</a> for search.')
      end

      it "preserves legitimate query parameters while stripping tracking ones" do
        task = Raif::TestHtmlTask.new(raw_response: "Search [results](https://example.com?q=ruby&page=2&utm_source=google) here.")
        expect(task.parsed_response).to eq('Search <a href="https://example.com?q=ruby&amp;page=2">results</a> here.')
      end

      it "handles URLs without query parameters" do
        task = Raif::TestHtmlTask.new(raw_response: "Visit [Example](https://example.com) site.")
        expect(task.parsed_response).to eq('Visit <a href="https://example.com">Example</a> site.')
      end

      it "handles mixed case tracking parameters" do
        task = Raif::TestHtmlTask.new(raw_response: "Check [this](https://example.com?Utm_Source=email) link.")
        expect(task.parsed_response).to eq('Check <a href="https://example.com">this</a> link.')
      end

      it "handles invalid URLs gracefully" do
        task = Raif::TestHtmlTask.new(raw_response: "Check [this](not-a-valid-url?utm_source=email) link.")
        expect(task.parsed_response).to eq('Check <a href="not-a-valid-url?utm_source=email">this</a> link.')
      end
    end
  end
end
