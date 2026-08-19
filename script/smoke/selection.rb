# frozen_string_literal: true

# Resolves which Raif::ModelManifest entries bin/smoke should run against for
# a given set of CLI selectors. A selector is one of:
#
#   * an exact model key (e.g. "anthropic_claude_5_sonnet"): an *explicit*
#     selection. The caller asked for this model by name, so Smoke::Policy
#     treats a missing credential or failed check on it as a run failure.
#   * "ALL" (case-insensitive) or a provider prefix (see PROVIDER_PREFIXES),
#     or a --stale threshold (the stale_days: keyword): a *pattern*
#     selection, a sweep across many models that should tolerate a provider
#     the caller has not configured credentials for.
#
# Retired entries are excluded from every selector, including an exact key
# match against a retired model's own key: a retired model has no live API
# left to smoke-test.
module Smoke
  module Selection
    PROVIDER_PREFIXES = {
      "anthropic" => ->(key) { key.start_with?("anthropic_") },
      "bedrock" => ->(key) { key.start_with?("bedrock_") },
      "open_ai" => ->(key) { key.start_with?("open_ai_") && !key.start_with?("open_ai_responses_") },
      "open_ai_responses" => ->(key) { key.start_with?("open_ai_responses_") },
      "open_router" => ->(key) { key.start_with?("open_router_") },
      "google" => ->(key) { key.start_with?("google_") },
      "x_ai" => ->(key) { key.start_with?("x_ai_") }
    }.freeze

    EMBEDDINGS_SELECTOR = "embeddings"

    # argv_selectors - raw CLI selector strings (e.g. ARGV after option parsing).
    # entries - Raif::ModelManifest::Entry objects (LLM models; not embeddings).
    # stale_days - optional --stale N threshold, applied in addition to argv_selectors.
    # embedding_entries - Raif::ModelManifest::EmbeddingEntry objects, returned (minus retired) under
    #   the "embeddings" selector. Kept as its own keyword rather than mixed into `entries` because
    #   embedding entries don't share Entry's capability/verification schema and drive a different
    #   check entirely (an embedding generation smoke test, not the capability matrix).
    #
    # Returns { entries:, embedding_entries:, explicit_keys:, unknown: }.
    def self.resolve(argv_selectors, entries, stale_days: nil, embedding_entries: [])
      live_entries = entries.reject(&:retired?)
      entries_by_key = live_entries.to_h { |entry| [entry.key.to_s, entry] }

      selected = {}
      explicit_keys = []
      unknown = []
      embeddings_selected = false

      argv_selectors.each do |raw_selector|
        selector = raw_selector.to_s

        if selector.casecmp("ALL").zero?
          live_entries.each { |entry| selected[entry.key] = entry }
        elsif selector == EMBEDDINGS_SELECTOR
          embeddings_selected = true
        elsif PROVIDER_PREFIXES.key?(selector)
          matcher = PROVIDER_PREFIXES.fetch(selector)
          live_entries.each { |entry| selected[entry.key] = entry if matcher.call(entry.key.to_s) }
        elsif entries_by_key.key?(selector)
          selected[entries_by_key[selector].key] = entries_by_key[selector]
          explicit_keys << selector
        else
          unknown << selector
        end
      end

      if stale_days
        live_entries.each do |entry|
          selected[entry.key] = entry if entry.unverified_capabilities(stale_after_days: stale_days).any?
        end
      end

      {
        entries: selected.values,
        embedding_entries: embeddings_selected ? embedding_entries.reject(&:retired?) : [],
        explicit_keys: explicit_keys,
        unknown: unknown
      }
    end
  end
end
