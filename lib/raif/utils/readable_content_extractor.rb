# frozen_string_literal: true

class Raif::Utils::ReadableContentExtractor
  attr_reader :raw_html

  def initialize(raw_html)
    @raw_html = raw_html
  end

  TAG_REMOVE_LIST = [
    "a",
    "button",
    "form",
    "iframe",
    "img",
    "input",
    "label",
    "nav",
    "noscript",
    "script",
    "style",
    "svg",
    "footer"
  ]

  # This will first remove all tags in TAG_REMOVE_LIST and their children.
  # Things in TAG_REMOVE_LIST are things that we do not consider likely to contain readable content.
  # We also call scrub!(:strip) to remove anything unsafe, but leave the text content.
  def extract_readable_content
    body_content = Loofah.html5_document(raw_html).at("body")
    return raw_html unless body_content

    scrubbed_html = body_content
      .scrub!(readable_content_scrubber)
      .scrub!(empty_node_scrubber)
      .scrub!(:strip)

    scrubbed_html.inner_html
  end

  def readable_content_scrubber
    @readable_content_scrubber ||= Loofah::Scrubber.new do |node|
      # if the node is something we don't consider readable content, remove it entirely
      node.remove if TAG_REMOVE_LIST.include?(node.name)

      # strip all attributes from the tags
      node.attributes.each { |attr| node.remove_attribute(attr.first) }

      # remove html comments
      node.remove if node.comment?
    end
  end

  def empty_node_scrubber
    # remove empty nodes from the bottom up so any parents that have only empty children also get removed
    @empty_node_scrubber ||= Loofah::Scrubber.new(direction: :bottom_up) do |node|
      node.remove if node.children.empty? && node.text.strip.empty?
    end
  end

end
