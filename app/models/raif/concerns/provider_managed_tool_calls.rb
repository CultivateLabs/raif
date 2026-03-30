# frozen_string_literal: true

module Raif::Concerns::ProviderManagedToolCalls
  extend ActiveSupport::Concern

  # Provider-managed tool data is not normalized by the provider SDKs the same
  # way developer-managed tool calls are. This method smooths those differences
  # into one admin-friendly structure for the model completion page.
  def provider_managed_tool_calls
    # Memoized for repeated reads during a request/render. This assumes the
    # completion's response payload is not mutated after first access.
    @provider_managed_tool_calls ||= begin
      tool_calls = extract_provider_managed_tool_calls
      tool_calls = inferred_provider_managed_tool_calls if tool_calls.empty?

      tool_calls.map do |tool_call|
        next tool_call unless tool_call["tool_name"] == "web_search"

        # Search sources can come from explicit provider result blocks
        # (Anthropic) or from top-level citations (OpenAI / Google), so we
        # merge both.
        tool_call.merge("sources" => merge_provider_managed_sources(tool_call["sources"], citations))
      end
    end
  end

private

  def extract_provider_managed_tool_calls
    response_blocks = Array(response_array).select { |block| block.is_a?(Hash) }
    result_blocks_by_tool_use_id = response_blocks.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |block, hash|
      next if block["tool_use_id"].blank?

      hash[block["tool_use_id"]] << block
    end

    response_blocks.filter_map do |block|
      case block["type"]
      when "server_tool_use"
        # Anthropic stores the tool invocation in one block and the result in a
        # separate block keyed by `tool_use_id`.
        build_provider_managed_server_tool_call(block, result_blocks_by_tool_use_id)
      else
        # OpenAI Responses persists provider-managed calls as top-level typed
        # blocks like `web_search_call`, `code_interpreter`, etc.
        build_provider_managed_tool_call_from_type(block)
      end
    end
  end

  def build_provider_managed_server_tool_call(block, result_blocks_by_tool_use_id)
    tool_name = normalize_provider_managed_tool_name(block["name"])
    return unless provider_managed_tool_available?(tool_name)

    raw_result = result_blocks_by_tool_use_id[block["id"]].presence
    {
      "tool_name" => tool_name,
      "provider_tool_call_id" => block["id"],
      "status" => block["status"],
      "arguments" => block["input"].presence,
      "sources" => extract_provider_managed_sources(raw_result),
      "raw_result" => raw_result,
      "inferred" => false
    }
  end

  def build_provider_managed_tool_call_from_type(block)
    tool_name = normalize_provider_managed_tool_name(block["type"])
    return unless provider_managed_tool_available?(tool_name)

    payload = block.except("id", "type", "status").presence
    {
      "tool_name" => tool_name,
      "provider_tool_call_id" => block["id"],
      "status" => block["status"],
      "arguments" => payload,
      "sources" => [],
      "raw_result" => payload,
      "inferred" => false
    }
  end

  def inferred_provider_managed_tool_calls
    # Google currently gives us citations for provider-managed web search, but
    # not a first-class tool call block in `response_array`, so we infer a
    # single search invocation when web search was available and citations exist.
    return [] unless provider_managed_tool_available?("web_search") && citations.present?

    [{
      "tool_name" => "web_search",
      "provider_tool_call_id" => nil,
      "status" => "completed",
      "arguments" => nil,
      "sources" => merge_provider_managed_sources([], citations),
      "raw_result" => nil,
      "inferred" => true
    }]
  end

  def extract_provider_managed_sources(result_blocks)
    Array(result_blocks).flat_map do |result_block|
      Array(result_block["content"]).filter_map do |content_block|
        next unless content_block.is_a?(Hash) && content_block["type"] == "web_search_result"

        {
          "title" => content_block["title"],
          "url" => normalize_provider_managed_source_url(content_block["url"]),
          "page_age" => content_block["page_age"]
        }.compact
      end
    end.uniq { |source| source["url"].presence || source["title"] }
  end

  def merge_provider_managed_sources(existing_sources, extra_sources)
    Array(existing_sources).concat(Array(extra_sources)).filter_map do |source|
      next unless source.is_a?(Hash)

      {
        "title" => source["title"],
        "url" => normalize_provider_managed_source_url(source["url"]),
        "page_age" => source["page_age"]
      }.compact.presence
    end.uniq { |source| source["url"].presence || source["title"] }
  end

  def normalize_provider_managed_tool_name(name)
    case name.to_s
    when "web_search", "web_search_call", "web_search_preview"
      "web_search"
    when "code_execution", "code_interpreter", "code_interpreter_call"
      "code_execution"
    when "image_generation", "image_generation_call"
      "image_generation"
    end
  end

  def provider_managed_tool_available?(tool_name)
    return false if tool_name.blank?

    available_model_tools_map[tool_name]&.provider_managed?
  end

  def normalize_provider_managed_source_url(url)
    return if url.blank?

    Raif::Utils::HtmlFragmentProcessor.strip_tracking_parameters(url)
  end
end
