# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Utils::HtmlFragmentProcessor do
  describe ".clean_html_fragment" do
    context "when cleaning HTML content" do
      it "removes empty text nodes" do
        html = "<p>Hello</p>  <div>  </div><span>World</span>"
        result = described_class.clean_html_fragment(html)
        expect(result).not_to include("  ")
      end

      it "sanitizes dangerous HTML tags by default" do
        html = "<script>alert('xss')</script><p>Safe content</p>"
        result = described_class.clean_html_fragment(html)
        expect(result).not_to include("<script>")
        expect(result).to include("Safe content")
      end

      it "allows custom allowed_tags" do
        html = "<p>Paragraph</p><div>Div content</div><span>Span content</span>"
        result = described_class.clean_html_fragment(html, allowed_tags: %w[p span])
        expect(result).to include("<p>Paragraph</p>")
        expect(result).to include("<span>Span content</span>")
        expect(result).not_to include("<div>")
        expect(result).to include("Div content") # content should remain
      end

      it "allows custom allowed_attributes" do
        html = '<p class="test" id="para">Content</p>'
        result = described_class.clean_html_fragment(html, allowed_attributes: %w[class])
        expect(result).to include('class="test"')
        expect(result).not_to include('id="para"')
      end

      it "strips leading and trailing whitespace from result" do
        html = "  <p>Content</p>  "
        result = described_class.clean_html_fragment(html)
        expect(result).to eq("<p>Content</p>")
      end

      it "handles empty input" do
        result = described_class.clean_html_fragment("")
        expect(result).to eq("")
      end

      it "handles nil input gracefully" do
        expect { described_class.clean_html_fragment(nil) }.not_to raise_error
      end
    end
  end

  describe ".convert_markdown_links_to_html" do
    context "when converting markdown links" do
      it "converts simple markdown links to HTML" do
        markdown = "Check out [Google](https://google.com) for search."
        result = described_class.convert_markdown_links_to_html(markdown)
        expected = 'Check out <a href="https://google.com" target="_blank" rel="noopener">Google</a> for search.'
        expect(result).to eq(expected)
      end

      it "converts multiple markdown links" do
        markdown = "Visit [Google](https://google.com) and [GitHub](https://github.com)"
        result = described_class.convert_markdown_links_to_html(markdown)
        expect(result).to include('<a href="https://google.com" target="_blank" rel="noopener">Google</a>')
        expect(result).to include('<a href="https://github.com" target="_blank" rel="noopener">GitHub</a>')
      end

      it "handles links with tracking parameters by stripping them" do
        markdown = "[Example](https://example.com?utm_source=test&regular_param=keep)"
        result = described_class.convert_markdown_links_to_html(markdown)
        expect(result).to include('href="https://example.com?regular_param=keep"')
        expect(result).not_to include("utm_source")
      end

      it "handles empty link text" do
        markdown = "[](https://example.com)"
        result = described_class.convert_markdown_links_to_html(markdown)
        expect(result).to include('<a href="https://example.com" target="_blank" rel="noopener"></a>')
      end

      it "handles links with special characters in text" do
        markdown = "[Test & Example](https://example.com)"
        result = described_class.convert_markdown_links_to_html(markdown)
        expect(result).to include(">Test &amp; Example</a>")
      end

      it "leaves non-markdown links unchanged" do
        text = "Visit https://example.com directly"
        result = described_class.convert_markdown_links_to_html(text)
        expect(result).to eq(text)
      end

      it "handles malformed markdown links" do
        text = "[Incomplete link without closing paren](https://example.com"
        result = described_class.convert_markdown_links_to_html(text)
        expect(result).to eq(text) # Should remain unchanged
      end
    end
  end

  describe ".process_links" do
    context "when processing links with default options" do
      it "adds target='_blank' and rel='noopener' to a simple link" do
        html = '<p>Check out <a href="https://example.com">this link</a></p>'
        result = described_class.process_links(html, add_target_blank: true, strip_tracking_parameters: true)
        expect(result).to include('<a href="https://example.com" target="_blank" rel="noopener">this link</a>')
      end

      it "adds attributes to multiple links" do
        html = '<p>Visit <a href="https://google.com">Google</a> and <a href="https://github.com">GitHub</a></p>'
        result = described_class.process_links(html, add_target_blank: true, strip_tracking_parameters: true)
        expect(result).to include('<a href="https://google.com" target="_blank" rel="noopener">Google</a>')
        expect(result).to include('<a href="https://github.com" target="_blank" rel="noopener">GitHub</a>')
      end

      it "overwrites existing target and rel attributes" do
        html = '<a href="https://example.com" target="_self" rel="nofollow">Link</a>'
        result = described_class.process_links(html, add_target_blank: true, strip_tracking_parameters: true)
        expect(result).to include('target="_blank"')
        expect(result).to include('rel="noopener"')
        expect(result).not_to include('target="_self"')
        expect(result).not_to include('rel="nofollow"')
      end

      it "preserves other link attributes" do
        html = '<a href="https://example.com" class="btn" id="link1" data-test="value">Link</a>'
        result = described_class.process_links(html, add_target_blank: true, strip_tracking_parameters: true)
        expect(result).to include('class="btn"')
        expect(result).to include('id="link1"')
        expect(result).to include('data-test="value"')
        expect(result).to include('target="_blank"')
        expect(result).to include('rel="noopener"')
      end

      it "strips tracking parameters from links by default" do
        html = '<a href="https://example.com?utm_source=test&utm_medium=cpc&regular_param=keep">Link</a>'
        result = described_class.process_links(html, add_target_blank: true, strip_tracking_parameters: true)
        expect(result).to include('href="https://example.com?regular_param=keep"')
        expect(result).not_to include("utm_source")
        expect(result).not_to include("utm_medium")
      end

      it "handles links within complex HTML structure" do
        html = '<div><p>Text with <a href="/path">internal link</a> and <span>more <a href="https://external.com">external</a></span></p></div>'
        result = described_class.process_links(html, add_target_blank: true, strip_tracking_parameters: true)
        expect(result).to include('<a href="/path" target="_blank" rel="noopener">internal link</a>')
        expect(result).to include('<a href="https://external.com" target="_blank" rel="noopener">external</a>')
        expect(result).to include("<div>")
        expect(result).to include("<span>")
      end

      it "handles HTML without any links" do
        html = "<p>This is just text with no links.</p><div>More content</div>"
        result = described_class.process_links(html, add_target_blank: true, strip_tracking_parameters: true)
        expect(result).to eq(html)
      end

      it "handles empty input" do
        result = described_class.process_links("", add_target_blank: true, strip_tracking_parameters: true)
        expect(result).to eq("")
      end

      it "handles nil input gracefully" do
        expect { described_class.process_links(nil, add_target_blank: true, strip_tracking_parameters: true) }.not_to raise_error
      end

      it "handles links with various URL formats" do
        html = '
        <a href="https://example.com">HTTPS</a>
        <a href="http://example.com">HTTP</a>
        <a href="/relative/path">Relative</a>
        <a href="#anchor">Anchor</a>
        <a href="mailto:test@example.com">Email</a>
        <a href="tel:+1234567890">Phone</a>
        '
        result = described_class.process_links(html, add_target_blank: true, strip_tracking_parameters: true)

        expect(result).to include('<a href="https://example.com" target="_blank" rel="noopener">HTTPS</a>')
        expect(result).to include('<a href="http://example.com" target="_blank" rel="noopener">HTTP</a>')
        expect(result).to include('<a href="/relative/path" target="_blank" rel="noopener">Relative</a>')
        expect(result).to include('<a href="#anchor" target="_blank" rel="noopener">Anchor</a>')
        expect(result).to include('<a href="mailto:test@example.com" target="_blank" rel="noopener">Email</a>')
        expect(result).to include('<a href="tel:+1234567890" target="_blank" rel="noopener">Phone</a>')
      end

      it "handles malformed HTML gracefully" do
        html = '<a href="https://example.com">Unclosed link'
        result = described_class.process_links(html, add_target_blank: true, strip_tracking_parameters: true)
        expect(result).to include('target="_blank"')
        expect(result).to include('rel="noopener"')
      end

      it "preserves link content with HTML entities" do
        html = '<a href="https://example.com">Link with &amp; entity</a>'
        result = described_class.process_links(html, add_target_blank: true, strip_tracking_parameters: true)
        expect(result).to include('target="_blank"')
        expect(result).to include('rel="noopener"')
        expect(result).to include("Link with &amp; entity")
      end
    end

    context "when add_target_blank is false" do
      it "does not add target or rel attributes" do
        html = '<a href="https://example.com">Link</a>'
        result = described_class.process_links(html, add_target_blank: false, strip_tracking_parameters: true)
        expect(result).not_to include('target="_blank"')
        expect(result).not_to include('rel="noopener"')
        expect(result).to include('<a href="https://example.com">Link</a>')
      end

      it "still strips tracking parameters by default" do
        html = '<a href="https://example.com?utm_source=test&regular_param=keep">Link</a>'
        result = described_class.process_links(html, add_target_blank: false, strip_tracking_parameters: true)
        expect(result).to include('href="https://example.com?regular_param=keep"')
        expect(result).not_to include("utm_source")
        expect(result).not_to include('target="_blank"')
      end

      it "preserves existing target and rel attributes" do
        html = '<a href="https://example.com" target="_self" rel="nofollow">Link</a>'
        result = described_class.process_links(html, add_target_blank: false, strip_tracking_parameters: true)
        expect(result).to include('target="_self"')
        expect(result).to include('rel="nofollow"')
      end
    end

    context "when strip_tracking_parameters is false" do
      it "preserves tracking parameters in URLs" do
        html = '<a href="https://example.com?utm_source=test&utm_medium=cpc&regular_param=keep">Link</a>'
        result = described_class.process_links(html, add_target_blank: true, strip_tracking_parameters: false)
        expect(result).to include('href="https://example.com?utm_source=test&amp;utm_medium=cpc&amp;regular_param=keep"')
        expect(result).to include("utm_source")
        expect(result).to include("utm_medium")
      end

      it "still adds target blank by default" do
        html = '<a href="https://example.com?utm_source=test">Link</a>'
        result = described_class.process_links(html, add_target_blank: true, strip_tracking_parameters: false)
        expect(result).to include('target="_blank"')
        expect(result).to include('rel="noopener"')
        expect(result).to include("utm_source")
      end
    end

    context "when both options are false" do
      it "leaves links unchanged" do
        html = '<a href="https://example.com?utm_source=test" target="_self" rel="nofollow">Link</a>'
        result = described_class.process_links(html, add_target_blank: false, strip_tracking_parameters: false)
        expect(result).to eq(html)
      end
    end

    context "when processing links with tracking parameters" do
      it "removes UTM parameters from multiple links" do
        html = '<a href="https://example.com?utm_source=google&regular=keep">Link 1</a> <a href="https://test.com?utm_medium=cpc&other=value">Link 2</a>' # rubocop:disable Layout/LineLength
        result = described_class.process_links(html, add_target_blank: true, strip_tracking_parameters: true)
        expect(result).to include('href="https://example.com?regular=keep"')
        expect(result).to include('href="https://test.com?other=value"')
        expect(result).not_to include("utm_source")
        expect(result).not_to include("utm_medium")
      end

      it "handles links with only tracking parameters" do
        html = '<a href="https://example.com?utm_source=test&utm_medium=test">Link</a>'
        result = described_class.process_links(html, add_target_blank: true, strip_tracking_parameters: true)
        expect(result).to include('href="https://example.com"')
        expect(result).not_to include("utm_source")
      end

      it "handles case-insensitive UTM parameters" do
        html = '<a href="https://example.com?UTM_SOURCE=test&Utm_Medium=test&regular=keep">Link</a>'
        result = described_class.process_links(html, add_target_blank: true, strip_tracking_parameters: true)
        expect(result).to include('href="https://example.com?regular=keep"')
        expect(result).not_to include("UTM_SOURCE")
        expect(result).not_to include("Utm_Medium")
      end
    end
  end

  describe ".strip_tracking_parameters" do
    context "when stripping tracking parameters" do
      it "removes UTM parameters" do
        url = "https://example.com?utm_source=google&utm_medium=cpc&regular_param=keep"
        result = described_class.strip_tracking_parameters(url)
        expect(result).to eq("https://example.com?regular_param=keep")
      end

      it "removes all UTM parameters" do
        url = "https://example.com?utm_source=test&utm_medium=test&utm_campaign=test&utm_term=test&utm_content=test&utm_id=test"
        result = described_class.strip_tracking_parameters(url)
        expect(result).to eq("https://example.com")
      end

      it "handles case-insensitive UTM parameters" do
        url = "https://example.com?UTM_SOURCE=test&Utm_Medium=test&regular=keep"
        result = described_class.strip_tracking_parameters(url)
        expect(result).to eq("https://example.com?regular=keep")
      end

      it "preserves non-tracking parameters" do
        url = "https://example.com?page=1&limit=10&utm_source=test"
        result = described_class.strip_tracking_parameters(url)
        expect(result).to eq("https://example.com?page=1&limit=10")
      end

      it "handles URLs without query parameters" do
        url = "https://example.com/path"
        result = described_class.strip_tracking_parameters(url)
        expect(result).to eq(url)
      end

      it "handles URLs without question mark" do
        url = "https://example.com"
        result = described_class.strip_tracking_parameters(url)
        expect(result).to eq(url)
      end

      it "handles relative URLs" do
        url = "/path?utm_source=test&param=keep"
        result = described_class.strip_tracking_parameters(url)
        expect(result).to eq("/path?param=keep")
      end

      it "handles anchor URLs" do
        url = "#section?utm_source=test"
        result = described_class.strip_tracking_parameters(url)
        expect(result).to eq("#section?utm_source=test") # Fragment URLs don't have actual query parameters
      end

      it "handles invalid URLs gracefully" do
        invalid_url = "not-a-valid-url with spaces"
        result = described_class.strip_tracking_parameters(invalid_url)
        expect(result).to eq(invalid_url)
      end

      it "handles URLs with only tracking parameters" do
        url = "https://example.com?utm_source=test&utm_medium=test"
        result = described_class.strip_tracking_parameters(url)
        expect(result).to eq("https://example.com")
      end

      it "preserves URL fragments" do
        url = "https://example.com?utm_source=test&param=keep#fragment"
        result = described_class.strip_tracking_parameters(url)
        expect(result).to eq("https://example.com?param=keep#fragment")
      end

      it "handles URLs without scheme but with tracking params" do
        url = "example.com?utm_source=test&param=keep"
        result = described_class.strip_tracking_parameters(url)
        expect(result).to eq(url) # Should return unchanged for URLs without valid scheme
      end
    end
  end

  describe "TRACKING_PARAMS constant" do
    it "includes all expected UTM parameters" do
      expected_params = %w[
        utm_source
        utm_medium
        utm_campaign
        utm_term
        utm_content
        utm_id
      ]
      expect(described_class::TRACKING_PARAMS).to eq(expected_params)
    end
  end
end
