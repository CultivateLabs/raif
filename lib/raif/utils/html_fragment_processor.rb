# frozen_string_literal: true

# Utility class for processing HTML fragments with various cleaning and transformation operations.
#
# This class provides methods for sanitizing HTML content, converting markdown links to HTML,
# processing existing HTML links (adding target="_blank", stripping tracking parameters),
# and removing tracking parameters from URLs.
class Raif::Utils::HtmlFragmentProcessor
  # List of common tracking parameters to remove from URLs
  TRACKING_PARAMS = %w[
    utm_source
    utm_medium
    utm_campaign
    utm_term
    utm_content
    utm_id
  ]

  class << self
    # Cleans and sanitizes an HTML fragment by removing empty text nodes and dangerous content.
    #
    # @param html [String, Nokogiri::HTML::DocumentFragment] The HTML content to clean
    # @param allowed_tags [Array<String>, nil] Array of allowed HTML tags. Defaults to Rails HTML5 safe list
    # @param allowed_attributes [Array<String>, nil] Array of allowed HTML attributes. Defaults to Rails HTML5 safe list
    # @return [String] Cleaned and sanitized HTML string
    #
    # @example
    #   clean_html_fragment("<script>alert('xss')</script><p>Safe content</p>")
    #   # => "<p>Safe content</p>"
    #
    # @example With custom allowed tags
    #   clean_html_fragment("<p>Para</p><div>Div</div>", allowed_tags: %w[p])
    #   # => "<p>Para</p>Div"
    def clean_html_fragment(html, allowed_tags: nil, allowed_attributes: nil)
      fragment = html.is_a?(Nokogiri::HTML::DocumentFragment) ? html : Nokogiri::HTML.fragment(html)

      fragment.traverse do |node|
        if node.text? && node.text.strip.empty?
          node.remove
        end
      end

      allowed_tags = allowed_tags.presence || Rails::HTML5::SafeListSanitizer.allowed_tags
      allowed_attributes = allowed_attributes.presence || Rails::HTML5::SafeListSanitizer.allowed_attributes

      ActionController::Base.helpers.sanitize(fragment.to_html, tags: allowed_tags, attributes: allowed_attributes).strip
    end

    # Converts markdown-style links to HTML anchor tags with target="_blank" and rel="noopener".
    #
    # Converts [text](url) format to <a href="url" target="_blank" rel="noopener">text</a>.
    # Also strips tracking parameters from the URLs.
    #
    # @param text [String] The text content that may contain markdown links
    # @return [String] HTML with markdown links converted to anchor tags
    #
    # @example
    #   convert_markdown_links_to_html("Check out [Google](https://google.com) for search.")
    #   # => 'Check out <a href="https://google.com" target="_blank" rel="noopener">Google</a> for search.'
    #
    # @example With tracking parameters
    #   convert_markdown_links_to_html("[Example](https://example.com?utm_source=test&param=keep)")
    #   # => '<a href="https://example.com?param=keep" target="_blank" rel="noopener">Example</a>'
    def convert_markdown_links_to_html(text)
      # Convert markdown links [text](url) to HTML links <a href="url" target="_blank" rel="noopener">text</a>
      text.gsub(/\[([^\]]*)\]\(([^)]+)\)/) do |_match|
        text = ::Regexp.last_match(1)
        url = ::Regexp.last_match(2)
        clean_url = strip_tracking_parameters(url)
        %(<a href="#{CGI.escapeHTML(clean_url)}" target="_blank" rel="noopener">#{CGI.escapeHTML(text)}</a>)
      end
    end

    # Processes existing HTML links by optionally adding target="_blank" and stripping tracking parameters.
    #
    # This method provides fine-grained control over link processing with configurable options
    # for both target="_blank" addition and tracking parameter removal.
    #
    # @param html [String, Nokogiri::HTML::DocumentFragment] The HTML content containing links to process
    # @param add_target_blank [Boolean] Whether to add target="_blank" and rel="noopener" to links (required)
    # @param strip_tracking_parameters [Boolean] Whether to remove tracking parameters from URLs (required)
    # @return [String] Processed HTML with modified links
    #
    # @example Default behavior (adds target="_blank" and strips tracking params)
    #   process_links('<a href="https://example.com?utm_source=test">Link</a>', add_target_blank: true, strip_tracking_parameters: true)
    #   # => '<a href="https://example.com" target="_blank" rel="noopener">Link</a>'
    #
    # @example Only strip tracking parameters
    #   process_links(html, add_target_blank: false, strip_tracking_parameters: true)
    #   # => '<a href="https://example.com">Link</a>'
    #
    # @example Only add target="_blank"
    #   process_links(html, add_target_blank: true, strip_tracking_parameters: false)
    #   # => '<a href="https://example.com?utm_source=test" target="_blank" rel="noopener">Link</a>'
    #
    # @example No processing
    #   process_links(html, add_target_blank: false, strip_tracking_parameters: false)
    #   # => Original HTML unchanged
    def process_links(html, add_target_blank:, strip_tracking_parameters:)
      fragment = html.is_a?(Nokogiri::HTML::DocumentFragment) ? html : Nokogiri::HTML.fragment(html)

      fragment.css("a").each do |link|
        if add_target_blank
          link["target"] = "_blank"
          link["rel"] = "noopener"
        end

        if strip_tracking_parameters
          link["href"] = strip_tracking_parameters(link["href"])
        end
      end

      fragment.to_html
    end

    # Removes tracking parameters (UTM parameters) from a URL.
    #
    # Preserves all non-tracking query parameters and handles various URL formats including
    # relative URLs, absolute URLs, and malformed URLs gracefully.
    #
    # @param url [String] The URL to clean
    # @return [String] URL with tracking parameters removed, or original URL if parsing fails
    #
    # @example
    #   strip_tracking_parameters("https://example.com?utm_source=google&page=1")
    #   # => "https://example.com?page=1"
    #
    # @example Removes all tracking parameters
    #   strip_tracking_parameters("https://example.com?utm_source=test&utm_medium=cpc")
    #   # => "https://example.com"
    #
    # @example Preserves fragments
    #   strip_tracking_parameters("https://example.com?utm_source=test&page=1#section")
    #   # => "https://example.com?page=1#section"
    #
    # @example Handles relative URLs
    #   strip_tracking_parameters("/path?utm_source=test&param=keep")
    #   # => "/path?param=keep"
    def strip_tracking_parameters(url)
      return url unless url.include?("?")

      begin
        uri = URI.parse(url)
        return url unless uri.query

        # Only process URLs that have a valid scheme and host, or are relative URLs
        unless uri.scheme || url.start_with?("/", "#")
          return url
        end

        # Parse query parameters and filter out tracking ones
        params = URI.decode_www_form(uri.query)
        clean_params = params.reject { |param, _| TRACKING_PARAMS.include?(param.downcase) }

        # Rebuild the URL
        uri.query = if clean_params.empty?
          nil
        else
          URI.encode_www_form(clean_params)
        end

        uri.to_s
      rescue URI::InvalidURIError
        # If URL parsing fails, return the original URL
        url
      end
    end
  end
end
