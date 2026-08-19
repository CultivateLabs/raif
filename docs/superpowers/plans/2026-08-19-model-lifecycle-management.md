# Model Lifecycle Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the manifest-driven model lifecycle system: YAML manifest as single source of truth, a generator that emits the registry and derived docs, a consolidated capability-matrix smoke runner, runtime deprecation warnings, and three interactive Claude commands.

**Architecture:** `model_manifest/*.yml` holds every model's identity, pricing, capabilities, lifecycle, and verification state. `bin/generate_llm_registry` emits `lib/raif/default_llms.rb`, `lib/raif/default_embedding_models.rb`, the locale model-name sections, the initializer template key list, and setup doc key lists. `bin/smoke` derives a per-model test matrix from manifest claims and records results back. `Raif::Llm` gains deprecation attributes that produce runtime warnings and admin badges.

**Tech Stack:** Ruby / Rails engine, RSpec, YAML (Psych), OptionParser scripts run via `spec/dummy/bin/rails runner`.

**Spec:** `docs/superpowers/specs/2026-08-18-model-lifecycle-design.md` (read it first; this plan implements it exactly).

## Global Constraints

- **NEVER `git push`. NEVER open a PR.** Local commits only; the user reviews everything before anything leaves the machine. If a step here says commit, that means a local commit.
- No em dashes or en dashes anywhere: not in CHANGELOG, code comments, commit messages, or docs. Use plain punctuation.
- No `Co-Authored-By` or any AI attribution trailer in commit messages.
- Keep all docs/CHANGELOG text generic to raif. Never reference arc, CultivateLabs apps, or any host app.
- Use `/Users/brian/.asdf/shims/bundle` for every bundle invocation (a `bin/bundle` shim elsewhere on PATH shadows it). Abbreviated below as `bundle`.
- Run specs from the repo root: `bundle exec rspec <path>`.
- Runner scripts execute inside the dummy app: `bundle exec spec/dummy/bin/rails runner script/<name>.rb` (that is what the `bin/*` wrappers do; follow the existing pattern in `bin/smoke_llm_models`).
- Generated files must carry a `GENERATED FILE - DO NOT EDIT` header naming `bin/generate_llm_registry`.
- Every capability listed in a manifest is explicit; the generator emits a `model_provider_settings` entry only where the manifest value differs from the adapter default (see `ADAPTER_DEFAULTS`).
- The full test suite must pass at the end of every task: `bundle exec rspec`.

---

### Task 0: Branch and commit the design docs

**Files:**
- Commit: `docs/superpowers/specs/2026-08-18-model-lifecycle-design.md`, `docs/superpowers/plans/2026-08-19-model-lifecycle-management.md`

- [ ] **Step 1: Create the branch from main**

```bash
git checkout main && git pull && git checkout -b feature/model-lifecycle-management
```

(Do not push. The pre-existing untracked `docs/handoffs/` files are unrelated; leave them untracked.)

- [ ] **Step 2: Commit the spec and this plan**

```bash
git add docs/superpowers/
git commit -m "Add model lifecycle management design spec and implementation plan"
```

---

### Task 1: Manifest loader (`Raif::ModelManifest`)

The loader is the single API every other component consumes. It reads `model_manifest/*.yml` and returns flat, per-registry-key `Entry` structs (OpenAI endpoint expansion happens here).

**Files:**
- Create: `lib/raif/model_manifest.rb`
- Create: `spec/fixtures/model_manifest/anthropic.yml`, `spec/fixtures/model_manifest/open_ai.yml`, `spec/fixtures/model_manifest/embeddings.yml`
- Test: `spec/lib/raif/model_manifest_spec.rb`

**Interfaces:**
- Consumes: nothing (pure YAML + stdlib).
- Produces (used by Tasks 2-13):
  - `Raif::ModelManifest.load(dir: Raif::ModelManifest::MANIFEST_DIR)` returns a `Manifest`
  - `Manifest#llm_entries` returns `[Entry]` in file/declaration order, expanded per registry key
  - `Manifest#embedding_entries` returns `[EmbeddingEntry]`
  - `Manifest#references_for(provider_name)` returns the provider's `references` hash
  - `Entry` fields: `key` (Symbol), `provider_name` (String), `endpoint` (String or nil; "completions"/"responses" for open_ai), `adapter_class_name` (String), `api_name`, `display_name`, `max_completion_tokens` (Integer or nil), `pricing` (`{"input_per_million" => Float, "output_per_million" => Float}`), `capabilities` (Hash of String keys per schema), `lifecycle` (Hash), `verification` (Hash or nil), `source_path` (String), `key_base` (String)
  - `Entry#status`, `Entry#active?`, `Entry#deprecated?`, `Entry#retired?`
  - `Entry#unverified_capabilities(stale_after_days: nil)` returns Array of capability name Strings whose verification record is missing, whose recorded `claimed` differs from the current claim, or whose `checked_at` is older than the threshold
  - Constants: `MANIFEST_DIR`, `PROVIDER_ADAPTERS`, `OPEN_AI_ENDPOINT_ADAPTERS`, `ADAPTER_ORDER`, `CAPABILITY_KEYS`, `LIFECYCLE_STATUSES`, `PROVIDER_MANAGED_TOOL_CLASSES`, `ADAPTER_DEFAULTS`

**NOT required at runtime:** do NOT add a `require "raif/model_manifest"` to `lib/raif.rb`. Scripts and specs require it explicitly.

- [ ] **Step 1: Confirm adapter structured-output defaults before encoding them**

```bash
grep -rn "supports_structured_outputs" app/models/raif/llms/ app/models/raif/concerns/llms/
```

Known from prior exploration: `open_ai_base.rb` defaults to `true`; `anthropic.rb` and `bedrock.rb` default to `false`. Record what OpenRouter, XAi, and Google default to (XAi and OpenRouter likely inherit or mirror the OpenAI-style default; Google check its adapter). Also confirm batch support per class:

```bash
grep -rln "SupportsBatchInference" app/models/raif/llms/
```

Expected: included in OpenAI, Anthropic, Google, XAi adapters; NOT Bedrock, NOT OpenRouter. Fill the `ADAPTER_DEFAULTS` values in Step 3 with the confirmed values (the table below marks the two to verify).

- [ ] **Step 2: Write the fixture manifests**

`spec/fixtures/model_manifest/anthropic.yml`:

```yaml
provider: anthropic
references:
  models_doc: https://docs.claude.com/en/docs/about-claude/models
  pricing: https://claude.com/pricing
  deprecations: https://docs.claude.com/en/docs/about-claude/model-deprecations
models:
  - key: anthropic_test_model
    api_name: claude-test-1
    display_name: Anthropic Test Model
    max_completion_tokens: 64000
    pricing:
      input_per_million: 3.0
      output_per_million: 15.0
    capabilities:
      temperature: false
      structured_outputs: true
      native_tool_use: true
      streaming: true
      batch_inference: true
      images: true
      pdfs: true
      provider_managed_tools: [web_search, code_execution]
    lifecycle:
      status: active
      added_on: 2025-11-24
      deprecated_on: null
      retirement_date: null
      replacement_key: null
      migration_note: null
    verification:
      last_full_run_at: "2026-08-15T14:02:11Z"
      results:
        completion: { claimed: true, result: pass, checked_at: "2026-08-15T14:02:11Z" }
        streaming: { claimed: true, result: pass, checked_at: "2026-08-15T14:02:11Z" }
  - key: anthropic_old_model
    api_name: claude-old-1
    display_name: Anthropic Old Model
    max_completion_tokens: 32000
    pricing:
      input_per_million: 15.0
      output_per_million: 75.0
    capabilities:
      temperature: true
      structured_outputs: false
      native_tool_use: true
      streaming: true
      batch_inference: true
      images: true
      pdfs: true
      provider_managed_tools: []
    lifecycle:
      status: deprecated
      added_on: 2024-01-01
      deprecated_on: 2026-06-01
      retirement_date: 2026-12-01
      replacement_key: anthropic_test_model
      migration_note: null
    verification: null
```

`spec/fixtures/model_manifest/open_ai.yml` (exercises endpoint expansion, a responses-only model, and a retired model):

```yaml
provider: open_ai
references:
  models_doc: https://platform.openai.com/docs/models
  pricing: https://platform.openai.com/pricing
  deprecations: https://platform.openai.com/docs/deprecations
models:
  - key_base: gpt_test
    api_name: gpt-test-1
    display_name: OpenAI GPT Test
    pricing:
      input_per_million: 1.25
      output_per_million: 10.0
    lifecycle:
      status: active
      added_on: 2025-08-07
      deprecated_on: null
      retirement_date: null
      replacement_key: null
      migration_note: null
    endpoints:
      completions:
        capabilities:
          temperature: false
          structured_outputs: true
          native_tool_use: true
          streaming: true
          batch_inference: true
          images: true
          pdfs: false
          provider_managed_tools: []
        verification: null
      responses:
        capabilities:
          temperature: false
          structured_outputs: true
          native_tool_use: true
          streaming: true
          batch_inference: true
          images: true
          pdfs: true
          provider_managed_tools: [web_search, code_execution, image_generation]
        verification: null
  - key_base: gpt_test_pro
    api_name: gpt-test-pro
    display_name: OpenAI GPT Test Pro
    pricing:
      input_per_million: 15.0
      output_per_million: 120.0
    lifecycle:
      status: active
      added_on: 2025-10-06
      deprecated_on: null
      retirement_date: null
      replacement_key: null
      migration_note: null
    endpoints:
      responses:
        capabilities:
          temperature: false
          structured_outputs: true
          native_tool_use: true
          streaming: true
          batch_inference: false
          images: true
          pdfs: true
          provider_managed_tools: [web_search]
        verification: null
  - key_base: gpt_gone
    api_name: gpt-gone
    display_name: OpenAI GPT Gone
    pricing:
      input_per_million: 1.0
      output_per_million: 2.0
    lifecycle:
      status: retired
      added_on: 2023-01-01
      deprecated_on: 2025-01-01
      retirement_date: 2025-06-01
      replacement_key: gpt_test
      migration_note: null
    endpoints:
      completions:
        capabilities:
          temperature: true
          structured_outputs: false
          native_tool_use: true
          streaming: true
          batch_inference: true
          images: false
          pdfs: false
          provider_managed_tools: []
        verification: null
```

`spec/fixtures/model_manifest/embeddings.yml`:

```yaml
providers:
  - provider: open_ai
    adapter: Raif::EmbeddingModels::OpenAi
    models:
      - key: open_ai_test_embedding
        api_name: text-embedding-test
        display_name: OpenAI Test Embedding
        input_per_million: 0.02
        default_output_vector_size: 1536
        lifecycle:
          status: active
          added_on: 2024-01-25
          deprecated_on: null
          retirement_date: null
          replacement_key: null
          migration_note: null
        verification: null
```

- [ ] **Step 3: Write the failing loader spec**

`spec/lib/raif/model_manifest_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"
require "raif/model_manifest"

RSpec.describe Raif::ModelManifest do
  let(:fixture_dir) { Raif::Engine.root.join("spec/fixtures/model_manifest").to_s }
  let(:manifest) { described_class.load(dir: fixture_dir) }

  describe "#llm_entries" do
    it "expands open_ai models into one entry per endpoint with the endpoint prefix in the key" do
      keys = manifest.llm_entries.map(&:key)
      expect(keys).to include(:open_ai_gpt_test, :open_ai_responses_gpt_test)
      expect(keys).to include(:open_ai_responses_gpt_test_pro)
      expect(keys).not_to include(:open_ai_gpt_test_pro) # responses-only model
    end

    it "includes retired entries (callers filter on status)" do
      retired = manifest.llm_entries.select(&:retired?)
      expect(retired.map(&:key)).to eq([:open_ai_gpt_gone])
    end

    it "maps providers to adapter class names" do
      entry = manifest.llm_entries.find { |e| e.key == :anthropic_test_model }
      expect(entry.adapter_class_name).to eq("Raif::Llms::Anthropic")

      responses = manifest.llm_entries.find { |e| e.key == :open_ai_responses_gpt_test }
      expect(responses.adapter_class_name).to eq("Raif::Llms::OpenAiResponses")
      expect(responses.endpoint).to eq("responses")
      expect(responses.capabilities["pdfs"]).to eq(true)
      expect(responses.capabilities["provider_managed_tools"]).to eq(["web_search", "code_execution", "image_generation"])
    end

    it "carries pricing, display_name, max_completion_tokens, and lifecycle through" do
      entry = manifest.llm_entries.find { |e| e.key == :anthropic_test_model }
      expect(entry.pricing["input_per_million"]).to eq(3.0)
      expect(entry.display_name).to eq("Anthropic Test Model")
      expect(entry.max_completion_tokens).to eq(64000)
      expect(entry.lifecycle["status"]).to eq("active")
    end

    it "flags deprecated entries" do
      entry = manifest.llm_entries.find { |e| e.key == :anthropic_old_model }
      expect(entry).to be_deprecated
      expect(entry.lifecycle["replacement_key"]).to eq("anthropic_test_model")
    end
  end

  describe "Entry#unverified_capabilities" do
    it "returns capabilities with no verification record" do
      entry = manifest.llm_entries.find { |e| e.key == :anthropic_test_model }
      unverified = entry.unverified_capabilities
      expect(unverified).to include("structured_outputs", "batch_inference", "images", "pdfs")
      expect(unverified).not_to include("completion", "streaming")
    end

    it "treats a claim change as unverified" do
      entry = manifest.llm_entries.find { |e| e.key == :anthropic_test_model }
      entry.verification["results"]["streaming"]["claimed"] = false
      expect(entry.unverified_capabilities).to include("streaming")
    end

    it "treats everything as unverified when verification is null" do
      entry = manifest.llm_entries.find { |e| e.key == :anthropic_old_model }
      expect(entry.unverified_capabilities).to include("completion")
    end
  end

  describe "#embedding_entries" do
    it "loads embedding models with adapter and vector size" do
      entry = manifest.embedding_entries.find { |e| e.key == :open_ai_test_embedding }
      expect(entry.adapter_class_name).to eq("Raif::EmbeddingModels::OpenAi")
      expect(entry.default_output_vector_size).to eq(1536)
    end
  end

  describe "#references_for" do
    it "returns provider reference URLs" do
      expect(manifest.references_for("anthropic")["pricing"]).to eq("https://claude.com/pricing")
    end
  end
end
```

- [ ] **Step 4: Run it to make sure it fails**

Run: `bundle exec rspec spec/lib/raif/model_manifest_spec.rb`
Expected: LoadError (cannot load `raif/model_manifest`).

- [ ] **Step 5: Implement the loader**

`lib/raif/model_manifest.rb`:

```ruby
# frozen_string_literal: true

# Loads model_manifest/*.yml into plain structs. This file is intentionally
# NOT required by lib/raif.rb: the manifest is a maintenance-time artifact
# consumed by bin/generate_llm_registry, bin/smoke, and specs. The runtime
# registry is the generated lib/raif/default_llms.rb.
require "yaml"
require "date"
require "time"

module Raif
  module ModelManifest
    MANIFEST_DIR = File.expand_path("../../model_manifest", __dir__)

    PROVIDER_ADAPTERS = {
      "anthropic" => "Raif::Llms::Anthropic",
      "bedrock" => "Raif::Llms::Bedrock",
      "open_router" => "Raif::Llms::OpenRouter",
      "x_ai" => "Raif::Llms::XAi",
      "google" => "Raif::Llms::Google"
    }.freeze

    OPEN_AI_ENDPOINT_ADAPTERS = {
      "completions" => "Raif::Llms::OpenAiCompletions",
      "responses" => "Raif::Llms::OpenAiResponses"
    }.freeze

    OPEN_AI_ENDPOINT_KEY_PREFIXES = {
      "completions" => "open_ai_",
      "responses" => "open_ai_responses_"
    }.freeze

    ADAPTER_ORDER = [
      "Raif::Llms::OpenAiCompletions",
      "Raif::Llms::OpenAiResponses",
      "Raif::Llms::Anthropic",
      "Raif::Llms::Bedrock",
      "Raif::Llms::OpenRouter",
      "Raif::Llms::XAi",
      "Raif::Llms::Google"
    ].freeze

    CAPABILITY_KEYS = %w[
      temperature structured_outputs native_tool_use streaming
      batch_inference images pdfs provider_managed_tools
    ].freeze

    LIFECYCLE_STATUSES = %w[active deprecated retired].freeze

    PROVIDER_MANAGED_TOOL_CLASSES = {
      "web_search" => "Raif::ModelTools::ProviderManaged::WebSearch",
      "code_execution" => "Raif::ModelTools::ProviderManaged::CodeExecution",
      "image_generation" => "Raif::ModelTools::ProviderManaged::ImageGeneration"
    }.freeze

    # What each adapter class assumes when model_provider_settings says
    # nothing. The generator emits a settings entry only when the manifest
    # value differs from these. Values below marked VERIFY were confirmed in
    # Task 1 Step 1; update if the grep said otherwise.
    ADAPTER_DEFAULTS = {
      "Raif::Llms::OpenAiCompletions" => { "temperature" => true, "structured_outputs" => true, "batch_inference" => true },
      "Raif::Llms::OpenAiResponses" => { "temperature" => true, "structured_outputs" => true, "batch_inference" => true },
      "Raif::Llms::Anthropic" => { "temperature" => true, "structured_outputs" => false, "batch_inference" => true },
      "Raif::Llms::Bedrock" => { "temperature" => true, "structured_outputs" => false, "batch_inference" => false },
      "Raif::Llms::OpenRouter" => { "temperature" => true, "structured_outputs" => true, "batch_inference" => false }, # VERIFY structured_outputs
      "Raif::Llms::XAi" => { "temperature" => true, "structured_outputs" => true, "batch_inference" => true }, # VERIFY structured_outputs
      "Raif::Llms::Google" => { "temperature" => true, "structured_outputs" => true, "batch_inference" => true } # VERIFY structured_outputs
    }.freeze

    Entry = Struct.new(
      :key, :provider_name, :endpoint, :adapter_class_name, :api_name,
      :display_name, :max_completion_tokens, :pricing, :capabilities,
      :lifecycle, :verification, :source_path, :key_base,
      keyword_init: true
    ) do
      def status = lifecycle.fetch("status")
      def active? = status == "active"
      def deprecated? = status == "deprecated"
      def retired? = status == "retired"

      # Capabilities the smoke runner would test for this entry: "completion"
      # always, plus every schema capability, plus the derived
      # streaming_tool_calls when both streaming and native tool use are claimed.
      def smokable_capabilities
        caps = ["completion"]
        caps += CAPABILITY_KEYS.reject { |c| c == "provider_managed_tools" }
        caps << "provider_managed_tools" if capabilities["provider_managed_tools"]&.any?
        caps << "streaming_tool_calls" if capabilities["streaming"] && capabilities["native_tool_use"]
        caps
      end

      def claimed_value(capability)
        case capability
        when "completion" then true
        when "streaming_tool_calls" then capabilities["streaming"] && capabilities["native_tool_use"]
        when "provider_managed_tools" then capabilities["provider_managed_tools"]
        else capabilities[capability]
        end
      end

      def unverified_capabilities(stale_after_days: nil)
        results = verification&.dig("results") || {}
        smokable_capabilities.select do |cap|
          record = results[cap]
          next true if record.nil?
          next true if record["claimed"] != claimed_value(cap)

          if stale_after_days
            checked_at = Time.parse(record["checked_at"].to_s)
            next true if checked_at < Time.now - (stale_after_days * 86_400)
          end

          false
        end
      end
    end

    EmbeddingEntry = Struct.new(
      :key, :provider_name, :adapter_class_name, :api_name, :display_name,
      :input_per_million, :default_output_vector_size, :lifecycle,
      :verification, :source_path,
      keyword_init: true
    ) do
      def status = lifecycle.fetch("status")
      def active? = status == "active"
      def deprecated? = status == "deprecated"
      def retired? = status == "retired"
    end

    class Manifest
      attr_reader :llm_entries, :embedding_entries, :provider_files

      def initialize(llm_entries:, embedding_entries:, provider_references:, provider_files:)
        @llm_entries = llm_entries
        @embedding_entries = embedding_entries
        @provider_references = provider_references
        @provider_files = provider_files
      end

      def references_for(provider_name)
        @provider_references.fetch(provider_name, {})
      end
    end

    def self.load(dir: MANIFEST_DIR)
      llm_entries = []
      provider_references = {}
      provider_files = {}

      Dir[File.join(dir, "*.yml")].sort.each do |path|
        next if File.basename(path) == "embeddings.yml"

        data = YAML.safe_load_file(path, permitted_classes: [Date], aliases: true)
        provider = data.fetch("provider")
        provider_references[provider] = data["references"] || {}
        provider_files[provider] = path

        data.fetch("models").each do |model|
          llm_entries.concat(entries_for_model(provider, model, path))
        end
      end

      Manifest.new(
        llm_entries: llm_entries,
        embedding_entries: load_embeddings(File.join(dir, "embeddings.yml")),
        provider_references: provider_references,
        provider_files: provider_files
      )
    end

    def self.entries_for_model(provider, model, path)
      if provider == "open_ai"
        model.fetch("endpoints").map do |endpoint, endpoint_data|
          build_entry(
            provider: provider,
            model: model,
            path: path,
            key: :"#{OPEN_AI_ENDPOINT_KEY_PREFIXES.fetch(endpoint)}#{model.fetch("key_base")}",
            endpoint: endpoint,
            adapter: OPEN_AI_ENDPOINT_ADAPTERS.fetch(endpoint),
            capabilities: endpoint_data.fetch("capabilities"),
            verification: endpoint_data["verification"]
          )
        end
      else
        [
          build_entry(
            provider: provider,
            model: model,
            path: path,
            key: model.fetch("key").to_sym,
            endpoint: nil,
            adapter: PROVIDER_ADAPTERS.fetch(provider),
            capabilities: model.fetch("capabilities"),
            verification: model["verification"]
          )
        ]
      end
    end
    private_class_method :entries_for_model

    def self.build_entry(provider:, model:, path:, key:, endpoint:, adapter:, capabilities:, verification:)
      Entry.new(
        key: key,
        provider_name: provider,
        endpoint: endpoint,
        adapter_class_name: adapter,
        api_name: model.fetch("api_name"),
        display_name: model.fetch("display_name"),
        max_completion_tokens: model["max_completion_tokens"],
        pricing: model.fetch("pricing"),
        capabilities: capabilities,
        lifecycle: model.fetch("lifecycle"),
        verification: verification,
        source_path: path,
        key_base: model["key_base"] || model["key"]
      )
    end
    private_class_method :build_entry

    def self.load_embeddings(path)
      return [] unless File.exist?(path)

      data = YAML.safe_load_file(path, permitted_classes: [Date], aliases: true)
      data.fetch("providers").flat_map do |provider_block|
        provider_block.fetch("models").map do |model|
          EmbeddingEntry.new(
            key: model.fetch("key").to_sym,
            provider_name: provider_block.fetch("provider"),
            adapter_class_name: provider_block.fetch("adapter"),
            api_name: model.fetch("api_name"),
            display_name: model.fetch("display_name"),
            input_per_million: model.fetch("input_per_million"),
            default_output_vector_size: model.fetch("default_output_vector_size"),
            lifecycle: model.fetch("lifecycle"),
            verification: model["verification"],
            source_path: path
          )
        end
      end
    end
    private_class_method :load_embeddings
  end
end
```

- [ ] **Step 6: Run the spec until green**

Run: `bundle exec rspec spec/lib/raif/model_manifest_spec.rb`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/raif/model_manifest.rb spec/lib/raif/model_manifest_spec.rb spec/fixtures/model_manifest/
git commit -m "Add Raif::ModelManifest loader for model_manifest YAML files"
```

---

### Task 2: Extraction script and the real manifest files

One-time script that converts today's `Raif.default_llms`, embedding registry, and `en.yml` names into `model_manifest/*.yml`. Deleted in Task 8.

**Files:**
- Create: `script/extract_model_manifest.rb`
- Create (by running it): `model_manifest/anthropic.yml`, `model_manifest/bedrock.yml`, `model_manifest/open_ai.yml`, `model_manifest/open_router.yml`, `model_manifest/x_ai.yml`, `model_manifest/google.yml`, `model_manifest/embeddings.yml`

**Interfaces:**
- Consumes: `Raif.default_llms` (current hand-written hash), `Raif.default_embedding_models`, `I18n.t("raif.model_names")`, `Raif::ModelManifest::ADAPTER_DEFAULTS`.
- Produces: the seven manifest files, loadable by `Raif::ModelManifest.load`.

**Capability seeding rules** (encode these in the script):

- `temperature`: `!(settings[:supports_temperature] == false)`
- `structured_outputs`: `settings.key?(:supports_structured_outputs) ? settings[:supports_structured_outputs] : ADAPTER_DEFAULTS[adapter]["structured_outputs"]`
- `native_tool_use`: `config.fetch(:supports_native_tool_use, true)`
- `streaming`: `false` when the key matches `/\Abedrock_gpt_oss_/` (the current `Raif.config.streaming_unsupported_model_keys` default), else `true`
- `batch_inference`: `settings.key?(:supports_batch_inference) ? settings[:supports_batch_inference] : ADAPTER_DEFAULTS[adapter]["batch_inference"]`
- `provider_managed_tools`: reverse-map `supported_provider_managed_tools` class names through `PROVIDER_MANAGED_TOOL_CLASSES`
- `images` / `pdfs`: not modeled today; seed from this table (researched claims, truth-tested by the first `bin/smoke --all --record`):

| pattern | images | pdfs |
|---|---|---|
| `anthropic_*` | true | true |
| `bedrock_claude_*` | true | true |
| `bedrock_amazon_nova_*` | true | false |
| `bedrock_deepseek_*`, `bedrock_gpt_oss_*` | false | false |
| `open_ai_*` completions endpoint | true | false |
| `open_ai_responses_*` | true | true |
| `open_ai_*o1/o3/o4*` non-pro completions | true | false |
| `open_router_claude_*`, `open_router_gemini_*` | true | true |
| all other `open_router_*` | false | false |
| `x_ai_*` | true | false |
| `google_*` | true | true |

- `lifecycle`: `status: active`, `added_on: nil` (unknown history; leave null, valid per Task 3 rules), all other fields null
- `verification`: null
- `pricing per_million`: `("%.10g" % (cost * 1_000_000)).to_f` to undo float noise from the `/ 1000` Bedrock divisors
- `display_name`: copied verbatim from `I18n.t("raif.model_names")[key]` (and `embedding_model_names` for embeddings)
- OpenAI: group current completions + responses pairs by `key_base` (strip `open_ai_` / `open_ai_responses_` prefix); the 6 responses-only models (`o1_pro`, `o3_pro`, `gpt_5_pro`, `gpt_5_2_pro`, `gpt_5_4_pro`, `gpt_5_5_pro`) get only a `responses` endpoint
- YAML output: plain `data.to_yaml` (Psych defaults). Manifest files are normalized machine-writable YAML with no comments; every tool that edits them round-trips through Psych.

- [ ] **Step 1: Write `script/extract_model_manifest.rb`** implementing the rules above. Skeleton:

```ruby
# frozen_string_literal: true

# One-time bootstrap: converts the hand-written Raif.default_llms registry,
# the embedding registry, and config/locales/en.yml model names into
# model_manifest/*.yml. Deleted once the manifest becomes the source of truth.
require "raif/model_manifest"

ADAPTER_TO_PROVIDER = {
  "Raif::Llms::Anthropic" => "anthropic",
  "Raif::Llms::Bedrock" => "bedrock",
  "Raif::Llms::OpenRouter" => "open_router",
  "Raif::Llms::XAi" => "x_ai",
  "Raif::Llms::Google" => "google"
}.freeze

REFERENCES = {
  "open_ai" => {
    "models_doc" => "https://platform.openai.com/docs/models",
    "pricing" => "https://platform.openai.com/docs/pricing",
    "deprecations" => "https://platform.openai.com/docs/deprecations"
  },
  "anthropic" => {
    "models_doc" => "https://docs.claude.com/en/docs/about-claude/models",
    "pricing" => "https://claude.com/pricing",
    "deprecations" => "https://docs.claude.com/en/docs/about-claude/model-deprecations"
  },
  "bedrock" => {
    "models_doc" => "https://docs.aws.amazon.com/bedrock/latest/userguide/models-supported.html",
    "pricing" => "https://aws.amazon.com/bedrock/pricing/",
    "deprecations" => "https://docs.aws.amazon.com/bedrock/latest/userguide/model-lifecycle.html"
  },
  "open_router" => {
    "models_doc" => "https://openrouter.ai/models",
    "pricing" => "https://openrouter.ai/models",
    "deprecations" => "https://openrouter.ai/docs/models"
  },
  "x_ai" => {
    "models_doc" => "https://docs.x.ai/docs/models",
    "pricing" => "https://docs.x.ai/docs/models",
    "deprecations" => "https://docs.x.ai/docs/models"
  },
  "google" => {
    "models_doc" => "https://ai.google.dev/gemini-api/docs/models",
    "pricing" => "https://ai.google.dev/gemini-api/docs/pricing",
    "deprecations" => "https://ai.google.dev/gemini-api/docs/deprecations"
  }
}.freeze

# ... implement per the seeding rules in the plan, then:
# FileUtils.mkdir_p("model_manifest")
# File.write("model_manifest/#{provider}.yml", data.to_yaml)
```

Run it with: `bundle exec spec/dummy/bin/rails runner script/extract_model_manifest.rb`

- [ ] **Step 2: Run the extraction and eyeball the output**

Verify by loading: `bundle exec spec/dummy/bin/rails runner 'require "raif/model_manifest"; m = Raif::ModelManifest.load; puts m.llm_entries.size; puts m.embedding_entries.size'`
Expected: llm entry count equals `Raif.available_llm_keys.size - 1` when run in the dummy app... NOTE: run instead `puts Raif.default_llms.values.flatten.size` for the target count (the registry includes `raif_test_llm` only in test env; the manifest must NOT contain `raif_test_llm`). Embedding count: 5.

Spot-check `model_manifest/anthropic.yml` against `lib/raif/llm_registry.rb:265-385` (keys, api_names, per-million prices, max tokens) and display names against `config/locales/en.yml:55`.

- [ ] **Step 3: Commit (script + manifests)**

```bash
git add script/extract_model_manifest.rb model_manifest/
git commit -m "Bootstrap model_manifest from the current LLM registry"
```

---

### Task 3: Manifest validity spec

Offline CI guard on the real manifest files.

**Files:**
- Test: `spec/lib/raif/model_manifest_validity_spec.rb`

**Interfaces:**
- Consumes: `Raif::ModelManifest.load` (real `MANIFEST_DIR`).

- [ ] **Step 1: Write the spec**

```ruby
# frozen_string_literal: true

require "rails_helper"
require "raif/model_manifest"

RSpec.describe "model_manifest validity" do
  manifest = Raif::ModelManifest.load
  entries = manifest.llm_entries
  all_keys = entries.map(&:key)

  it "has unique keys" do
    expect(all_keys).to eq(all_keys.uniq)
  end

  entries.each do |entry|
    describe entry.key.to_s do
      it "prefixes the key with its provider" do
        prefix = entry.provider_name == "open_ai" ? Raif::ModelManifest::OPEN_AI_ENDPOINT_KEY_PREFIXES.fetch(entry.endpoint) : "#{entry.provider_name}_"
        expect(entry.key.to_s).to start_with(prefix)
      end

      it "has required fields" do
        expect(entry.api_name).to be_present
        expect(entry.display_name).to be_present
        expect(Raif::ModelManifest::LIFECYCLE_STATUSES).to include(entry.status)
      end

      it "has exactly the known capability keys" do
        expect(entry.capabilities.keys.sort).to eq(Raif::ModelManifest::CAPABILITY_KEYS.sort)
        entry.capabilities.except("provider_managed_tools").each_value do |v|
          expect([true, false]).to include(v)
        end
        expect(entry.capabilities["provider_managed_tools"] - Raif::ModelManifest::PROVIDER_MANAGED_TOOL_CLASSES.keys).to be_empty
      end

      it "has pricing unless retired" do
        next if entry.retired?

        expect(entry.pricing["input_per_million"]).to be_a(Numeric)
        expect(entry.pricing["output_per_million"]).to be_a(Numeric)
      end

      it "has coherent lifecycle fields" do
        if entry.deprecated?
          expect(entry.lifecycle["retirement_date"]).to be_present
        end

        replacement = entry.lifecycle["replacement_key"]
        if replacement
          target = entries.find { |e| e.key.to_s == replacement.to_s }
          expect(target).to be_present, "replacement_key #{replacement} not found in manifest"
          expect(target).to be_active, "replacement for a deprecated model must be active" if entry.deprecated?
        end
      end

      it "has well-formed verification records when present" do
        results = entry.verification&.dig("results") || {}
        expect(results.keys - entry.smokable_capabilities).to be_empty
        results.each_value do |record|
          expect(record).to include("claimed", "result", "checked_at")
        end
      end
    end
  end

  manifest.embedding_entries.each do |entry|
    describe entry.key.to_s do
      it "has required fields" do
        expect(entry.api_name).to be_present
        expect(entry.display_name).to be_present
        expect(entry.default_output_vector_size).to be_a(Integer)
        expect(Raif::ModelManifest::LIFECYCLE_STATUSES).to include(entry.status)
      end
    end
  end
end
```

- [ ] **Step 2: Run it; fix extraction bugs it surfaces, re-run until green**

Run: `bundle exec rspec spec/lib/raif/model_manifest_validity_spec.rb`
Expected: PASS (if it fails, the bug is in `script/extract_model_manifest.rb` or the schema; fix and re-extract).

- [ ] **Step 3: Commit**

```bash
git add spec/lib/raif/model_manifest_validity_spec.rb model_manifest/
git commit -m "Add manifest validity spec"
```

---

### Task 4: Registry data builder plus equivalence scaffolding

`RegistryData` turns manifest entries into the exact config hashes `Raif.default_llms` returns today. The temporary equivalence spec proves it against a verbatim snapshot before we delete the hand-written data.

**Files:**
- Create: `lib/raif/model_manifest/registry_data.rb`
- Create: `spec/fixtures/registry_equivalence/default_llms_snapshot.rb` (verbatim copy)
- Create: `spec/fixtures/registry_equivalence/model_names_snapshot.yml` (verbatim copy)
- Test: `spec/lib/raif/registry_equivalence_spec.rb` (temporary; deleted in Task 8)

**Interfaces:**
- Consumes: `Raif::ModelManifest.load`, `ADAPTER_DEFAULTS`.
- Produces (used by generator Task 5 and freshness spec Task 8):
  - `Raif::ModelManifest::RegistryData.llm_configs(manifest)` returns `{ "Raif::Llms::OpenAiCompletions" => [config Hash, ...], ... }` keyed by adapter class NAME (String), excluding retired entries, in `ADAPTER_ORDER`, entries in manifest order
  - `Raif::ModelManifest::RegistryData.embedding_configs(manifest)` same shape for embeddings
  - `Raif::ModelManifest::RegistryData.model_names(manifest)` returns `{ "anthropic_claude_5_sonnet" => "Anthropic Claude 5 Sonnet", ... }` for non-retired entries plus `"raif_test_llm" => "Raif Test LLM"`, alphabetical
  - `Raif::ModelManifest::RegistryData.embedding_model_names(manifest)` same for embeddings (no test entry)
  - `Raif::ModelManifest::RegistryData.streaming_unsupported_keys(manifest)` returns Array of key Strings where `capabilities["streaming"] == false`
  - Config hash shape per entry: `{ key:, api_name:, input_token_cost:, output_token_cost:, max_completion_tokens: (omitted if nil), model_provider_settings: (omitted if empty), supported_provider_managed_tools: (omitted if empty, array of Class constants), deprecated:/retirement_date:/replacement_key:/migration_note: (only when status deprecated) }`

- [ ] **Step 1: Create the snapshots**

Copy the body of `Raif.default_llms` from `lib/raif/llm_registry.rb:42-790` verbatim into `spec/fixtures/registry_equivalence/default_llms_snapshot.rb` as:

```ruby
# frozen_string_literal: true

# Temporary verbatim snapshot of the hand-written Raif.default_llms used only
# by spec/lib/raif/registry_equivalence_spec.rb during the manifest migration.
module RegistryEquivalenceSnapshot
  def self.default_llms
    # (paste the exact hash literal from lib/raif/llm_registry.rb here)
  end

  def self.default_embedding_models
    # (paste the exact hash literal from lib/raif/embedding_model_registry.rb here)
  end
end
```

Copy `config/locales/en.yml` lines under `model_names:` and `embedding_model_names:` into `spec/fixtures/registry_equivalence/model_names_snapshot.yml`:

```yaml
model_names:
  # (paste the exact mapping)
embedding_model_names:
  # (paste the exact mapping)
```

- [ ] **Step 2: Write the failing equivalence spec**

`spec/lib/raif/registry_equivalence_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"
require "raif/model_manifest"
require "raif/model_manifest/registry_data"
require Raif::Engine.root.join("spec/fixtures/registry_equivalence/default_llms_snapshot")

# Temporary migration guard: proves the manifest-generated registry data is
# equivalent to the hand-written registry before the hand-written data is
# deleted. Removed once lib/raif/default_llms.rb is generated (see plan Task 8).
RSpec.describe "registry equivalence" do
  let(:manifest) { Raif::ModelManifest.load }
  let(:generated) { Raif::ModelManifest::RegistryData.llm_configs(manifest) }
  let(:snapshot) do
    RegistryEquivalenceSnapshot.default_llms.transform_keys(&:name)
  end

  it "produces the same adapters" do
    expect(generated.keys).to match_array(snapshot.keys)
  end

  it "produces equivalent configs per adapter" do
    snapshot.each do |adapter_name, snapshot_configs|
      generated_configs = generated.fetch(adapter_name)
      expect(generated_configs.map { |c| c[:key] }).to eq(snapshot_configs.map { |c| c[:key] }),
        "key mismatch for #{adapter_name}"

      snapshot_configs.zip(generated_configs).each do |expected, actual|
        expect(actual[:api_name]).to eq(expected[:api_name])
        expect(actual[:input_token_cost]).to be_within(1e-12).of(expected[:input_token_cost])
        expect(actual[:output_token_cost]).to be_within(1e-12).of(expected[:output_token_cost])
        expect(actual[:max_completion_tokens]).to eq(expected[:max_completion_tokens])
        expect(actual.fetch(:model_provider_settings, {})).to eq(expected.fetch(:model_provider_settings, {})),
          "settings mismatch for #{expected[:key]}"
        expect(actual.fetch(:supported_provider_managed_tools, [])).to eq(expected.fetch(:supported_provider_managed_tools, [])),
          "tools mismatch for #{expected[:key]}"
      end
    end
  end

  it "produces equivalent embedding configs" do
    generated = Raif::ModelManifest::RegistryData.embedding_configs(manifest)
    RegistryEquivalenceSnapshot.default_embedding_models.transform_keys(&:name).each do |adapter_name, snapshot_configs|
      generated_configs = generated.fetch(adapter_name)
      snapshot_configs.zip(generated_configs).each do |expected, actual|
        expect(actual[:key]).to eq(expected[:key])
        expect(actual[:api_name]).to eq(expected[:api_name])
        expect(actual[:input_token_cost]).to be_within(1e-12).of(expected[:input_token_cost])
        expect(actual[:default_output_vector_size]).to eq(expected[:default_output_vector_size])
      end
    end
  end

  it "produces the exact current locale names" do
    names_snapshot = YAML.safe_load_file(
      Raif::Engine.root.join("spec/fixtures/registry_equivalence/model_names_snapshot.yml")
    )
    expect(Raif::ModelManifest::RegistryData.model_names(manifest)).to eq(names_snapshot["model_names"])
    expect(Raif::ModelManifest::RegistryData.embedding_model_names(manifest)).to eq(names_snapshot["embedding_model_names"])
  end

  it "reproduces the streaming blocklist default" do
    expect(Raif::ModelManifest::RegistryData.streaming_unsupported_keys(manifest))
      .to match_array(["bedrock_gpt_oss_120b", "bedrock_gpt_oss_20b"])
  end
end
```

- [ ] **Step 3: Run to verify it fails** (RegistryData does not exist yet)

Run: `bundle exec rspec spec/lib/raif/registry_equivalence_spec.rb`

- [ ] **Step 4: Implement `lib/raif/model_manifest/registry_data.rb`**

```ruby
# frozen_string_literal: true

require "raif/model_manifest"

module Raif
  module ModelManifest
    # Builds the runtime registry data structures from manifest entries.
    # Consumed by the generator (emitting them as Ruby literals) and by specs.
    module RegistryData
      def self.llm_configs(manifest)
        grouped = manifest.llm_entries.reject(&:retired?).group_by(&:adapter_class_name)
        ADAPTER_ORDER.each_with_object({}) do |adapter, out|
          entries = grouped[adapter] or next
          out[adapter] = entries.map { |entry| config_for(entry) }
        end
      end

      def self.config_for(entry)
        config = {
          key: entry.key,
          api_name: entry.api_name,
          input_token_cost: entry.pricing.fetch("input_per_million") / 1_000_000,
          output_token_cost: entry.pricing.fetch("output_per_million") / 1_000_000
        }
        config[:max_completion_tokens] = entry.max_completion_tokens if entry.max_completion_tokens

        settings = provider_settings_for(entry)
        config[:model_provider_settings] = settings if settings.any?

        tools = entry.capabilities.fetch("provider_managed_tools", [])
        if tools.any?
          config[:supported_provider_managed_tools] = tools.map { |t| PROVIDER_MANAGED_TOOL_CLASSES.fetch(t).constantize }
        end

        config[:supports_native_tool_use] = false unless entry.capabilities.fetch("native_tool_use")

        if entry.deprecated?
          config[:deprecated] = true
          config[:retirement_date] = entry.lifecycle["retirement_date"]
          config[:replacement_key] = entry.lifecycle["replacement_key"]&.to_sym
          config[:migration_note] = entry.lifecycle["migration_note"]
        end

        config
      end

      def self.provider_settings_for(entry)
        defaults = ADAPTER_DEFAULTS.fetch(entry.adapter_class_name)
        settings = {}
        settings[:supports_temperature] = entry.capabilities.fetch("temperature") if entry.capabilities.fetch("temperature") != defaults.fetch("temperature")
        settings[:supports_structured_outputs] = entry.capabilities.fetch("structured_outputs") if entry.capabilities.fetch("structured_outputs") != defaults.fetch("structured_outputs")
        settings[:supports_batch_inference] = entry.capabilities.fetch("batch_inference") if entry.capabilities.fetch("batch_inference") != defaults.fetch("batch_inference")
        settings
      end

      def self.embedding_configs(manifest)
        manifest.embedding_entries.reject(&:retired?).group_by(&:adapter_class_name).transform_values do |entries|
          entries.map do |entry|
            {
              key: entry.key,
              api_name: entry.api_name,
              input_token_cost: entry.input_per_million / 1_000_000,
              default_output_vector_size: entry.default_output_vector_size
            }
          end
        end
      end

      def self.model_names(manifest)
        names = manifest.llm_entries.reject(&:retired?).to_h { |e| [e.key.to_s, e.display_name] }
        names["raif_test_llm"] = "Raif Test LLM"
        names.sort.to_h
      end

      def self.embedding_model_names(manifest)
        manifest.embedding_entries.reject(&:retired?).to_h { |e| [e.key.to_s, e.display_name] }.sort.to_h
      end

      def self.streaming_unsupported_keys(manifest)
        manifest.llm_entries.reject(&:retired?).reject { |e| e.capabilities.fetch("streaming") }.map { |e| e.key.to_s }
      end
    end
  end
end
```

- [ ] **Step 5: Run the equivalence spec; iterate on extraction/ADAPTER_DEFAULTS until green**

Run: `bundle exec rspec spec/lib/raif/registry_equivalence_spec.rb`

Failures here mean one of: wrong `ADAPTER_DEFAULTS` value (fix the table AND re-check Task 1 Step 1), extraction seeded a capability wrong (fix `script/extract_model_manifest.rb`, re-run it, re-run validity spec), or `RegistryData` emission logic diverges. Iterate until PASS. This spec passing is the load-bearing proof of the whole migration.

- [ ] **Step 6: Commit**

```bash
git add lib/raif/model_manifest/registry_data.rb spec/lib/raif/registry_equivalence_spec.rb spec/fixtures/registry_equivalence/ model_manifest/ script/extract_model_manifest.rb
git commit -m "Add RegistryData builder with registry equivalence proof"
```

---

### Task 5: Generator (file emitters)

Turns `RegistryData` output into the four checked-in artifacts. Emitters are pure string builders (unit-testable); the script applies them to disk.

**Files:**
- Create: `lib/raif/model_manifest/generator.rb`
- Create: `script/generate_llm_registry.rb`, `bin/generate_llm_registry`
- Test: `spec/lib/raif/model_manifest_generator_spec.rb`

**Interfaces:**
- Consumes: `Raif::ModelManifest.load`, `RegistryData`.
- Produces:
  - `Generator.default_llms_rb(manifest)` returns String: full content of `lib/raif/default_llms.rb`
  - `Generator.default_embedding_models_rb(manifest)` returns String: full content of `lib/raif/default_embedding_models.rb`
  - `Generator.model_names_yaml_block(manifest)` / `Generator.embedding_model_names_yaml_block(manifest)` return String: the indented YAML lines INCLUDING the `    model_names:` header line, 4-space base indent matching `config/locales/en.yml`
  - `Generator.initializer_keys_block(manifest)` returns String: the comment lines between the initializer markers
  - `Generator.setup_md_keys_block(manifest, section)` returns String for `section` in `%w[open_ai open_ai_responses anthropic bedrock open_router google x_ai embeddings]`
  - `Generator.write_all!(manifest, root: Raif::Engine.root)` applies everything to disk; idempotent
  - `Generator.replace_yaml_section(file_content, section_key, replacement_block)` and `Generator.replace_between_markers(file_content, begin_marker, end_marker, replacement)` string helpers (also used by the freshness spec)

**Emission format rules:**
- Generated Ruby header:

```ruby
# frozen_string_literal: true

# GENERATED FILE - DO NOT EDIT.
# Source of truth: model_manifest/*.yml
# Regenerate with: bin/generate_llm_registry
```

- Costs emit as `#{value.to_s} / 1_000_000` where `value` is the Float read from the manifest (`to_s` on YAML Floats gives `"3.0"`, `"0.0115"`, `"1.25"`). Do NOT use `format("%g", ...)`: it would emit `3 / 1_000_000`, which is integer division in Ruby.
- `max_completion_tokens` emits with underscore separators: `128_000` (`n.to_s.gsub(/(\d)(?=(\d{3})+$)/, '\\1_')`).
- `model_provider_settings` emits inline: `model_provider_settings: { supports_temperature: false },`
- Tools emit multiline exactly as the current registry file does (array of constants).
- Deprecation fields emit as `deprecated: true, retirement_date: Date.new(2026, 12, 1), replacement_key: :x, migration_note: "..."` (omit nil fields; `migration_note` string must not contain em dashes).
- The generated `lib/raif/default_llms.rb` defines `Raif.default_llms` (same method, same return shape) AND `Raif.default_streaming_unsupported_model_keys` returning the frozen Array of key Strings from `RegistryData.streaming_unsupported_keys`.
- YAML name values: quote with double quotes only when the value contains `: `, `#`, or leading/trailing whitespace; otherwise plain scalars (matches current en.yml style).
- Initializer markers (in `lib/generators/raif/install/templates/initializer.rb`):

```
  # Available keys:
  # BEGIN GENERATED MODEL KEYS (bin/generate_llm_registry)
  #   open_ai_gpt_5_6_sol
  ...
  # END GENERATED MODEL KEYS
```

- setup.md markers (HTML comments, one pair per provider list):

```
<!-- BEGIN GENERATED MODEL KEYS: anthropic -->
- `anthropic_claude_5_fable`
...
<!-- END GENERATED MODEL KEYS: anthropic -->
```

- en.yml has NO markers: `replace_yaml_section` finds the line matching `/^    model_names:$/` and replaces through the last consecutive following line matching `/^      \S/`.

- [ ] **Step 1: Write failing emitter specs** covering, against the Task 1 fixture manifest: header present in `default_llms_rb`; a cost line emits `3.0 / 1_000_000`; the deprecated fixture model emits `deprecated: true`; retired fixture model absent; `model_names_yaml_block` alphabetical and includes `raif_test_llm: Raif Test LLM`; `replace_yaml_section` and `replace_between_markers` splice correctly on small synthetic strings; `write_all!` into a tmp copy is idempotent (second run changes nothing). Follow the shape of the Task 1 spec; assert with `include`/`eq` on exact emitted substrings.

- [ ] **Step 2: Run to verify failure, then implement `lib/raif/model_manifest/generator.rb`** per the interface and format rules above. The Ruby-literal emitter walks `RegistryData.llm_configs` and formats each config hash; keep one emit function per artifact.

- [ ] **Step 3: A semantic safety net spec** (permanent, lives in the generator spec file): evaluating the emitted `default_llms_rb` for the FIXTURE manifest in an anonymous module context and calling its `default_llms` must produce hashes equal to `RegistryData.llm_configs` for the same manifest (compare with the same tolerance approach as Task 4). This proves emitter text and data builder never drift.

- [ ] **Step 4: Write the script and wrapper**

`script/generate_llm_registry.rb`:

```ruby
# frozen_string_literal: true

# Regenerates all artifacts derived from model_manifest/*.yml.
# See bin/generate_llm_registry.
require "raif/model_manifest"
require "raif/model_manifest/registry_data"
require "raif/model_manifest/generator"

manifest = Raif::ModelManifest.load
Raif::ModelManifest::Generator.write_all!(manifest, root: Raif::Engine.root)
puts "Regenerated: lib/raif/default_llms.rb, lib/raif/default_embedding_models.rb, config/locales/en.yml (model names), initializer template, docs/_getting_started/setup.md"
```

`bin/generate_llm_registry` (mirror `bin/smoke_llm_models` exactly, swapping the script path; `chmod +x`).

- [ ] **Step 5: Run generator specs until green**

Run: `bundle exec rspec spec/lib/raif/model_manifest_generator_spec.rb`

- [ ] **Step 6: Commit**

```bash
git add lib/raif/model_manifest/generator.rb script/generate_llm_registry.rb bin/generate_llm_registry spec/lib/raif/model_manifest_generator_spec.rb
git commit -m "Add registry generator emitting Ruby, locale, initializer, and docs artifacts"
```

---

### Task 6: Wire-up: generated files replace the hand-written registry data

**Files:**
- Modify: `lib/raif/llm_registry.rb` (delete `default_llms`, keep machinery at lines 1-41)
- Modify: `lib/raif/embedding_model_registry.rb` (delete `default_embedding_models`, keep machinery)
- Create (generated): `lib/raif/default_llms.rb`, `lib/raif/default_embedding_models.rb`
- Modify: `lib/raif.rb` (add requires next to the existing `require "raif/llm_registry"` line)
- Modify: `lib/raif/configuration.rb:206` (streaming default now comes from generated data)
- Modify: `lib/generators/raif/install/templates/initializer.rb` (place markers once around the existing key list)
- Modify: `docs/_getting_started/setup.md` (place markers once around each provider list; also move the stale completions-model list under the correct OpenAI heading while adding markers)

**Interfaces:**
- Consumes: `Generator.write_all!`.
- Produces: `Raif.default_llms` (generated, same shape), `Raif.default_streaming_unsupported_model_keys`.

- [ ] **Step 1: Place the markers by hand** in the initializer template and setup.md per Task 5's marker formats. In setup.md there are provider lists under each of: OpenAI (add a completions list + a responses list with distinct markers `open_ai` and `open_ai_responses`), Anthropic, AWS Bedrock, OpenRouter, Google AI, xAI, and the embedding models section. The content between markers will be overwritten by the generator, so placement is what matters.

- [ ] **Step 2: Run the generator against the real manifest**

```bash
bin/generate_llm_registry
git diff --stat
```

Expected: `lib/raif/default_llms.rb` and `lib/raif/default_embedding_models.rb` created; en.yml `model_names`/`embedding_model_names` sections rewritten (diff should be empty or whitespace-only if extraction was faithful); marker contents populated.

- [ ] **Step 3: Delete the hand-written data and wire requires**

- In `lib/raif/llm_registry.rb`: delete `def self.default_llms ... end` (lines 42-790).
- In `lib/raif/embedding_model_registry.rb`: delete `def self.default_embedding_models ... end`.
- In `lib/raif.rb`: after the line requiring `raif/llm_registry`, add `require "raif/default_llms"` and after the embedding registry require add `require "raif/default_embedding_models"` (find exact lines with `grep -n "llm_registry\|embedding_model_registry" lib/raif.rb`).
- In `lib/raif/configuration.rb` replace line 206:

```ruby
      @streaming_unsupported_model_keys = Raif.default_streaming_unsupported_model_keys.dup
```

Keep the explanatory comment above it, updated: the default now comes from `model_manifest/` capability data (`streaming: false`) via the generated registry. Check for specs pinning the old regex default: `grep -rn "streaming_unsupported" spec/` and update any that assert the regex to assert the two `bedrock_gpt_oss_*` keys instead.

- [ ] **Step 4: Full suite**

Run: `bundle exec rspec`
Expected: PASS, including the equivalence spec (which now compares generated-and-loaded data against the snapshot) and the existing `spec/models/raif/llm_spec.rb:451` locale test.

- [ ] **Step 5: Lint**

Run: `bin/lint`
Expected: clean (i18n-tasks confirms en.yml stayed normalized; rubocop may need the generated files excluded; if rubocop complains about the generated file, add to `.rubocop.yml`:)

```yaml
AllCops:
  Exclude:
    - lib/raif/default_llms.rb
    - lib/raif/default_embedding_models.rb
```

(Merge into the existing `Exclude` list if one exists; check with `grep -n "Exclude" .rubocop.yml`.)

- [ ] **Step 6: Commit**

```bash
git add -A lib/ config/locales/en.yml docs/_getting_started/setup.md .rubocop.yml
git commit -m "Generate the LLM registry data from model_manifest"
```

---

### Task 7: Freshness spec

**Files:**
- Test: `spec/lib/raif/generated_artifacts_spec.rb`

- [ ] **Step 1: Write the spec**

```ruby
# frozen_string_literal: true

require "rails_helper"
require "raif/model_manifest"
require "raif/model_manifest/registry_data"
require "raif/model_manifest/generator"

RSpec.describe "generated artifacts freshness" do
  manifest = Raif::ModelManifest.load
  generator = Raif::ModelManifest::Generator
  hint = "Artifacts are stale. Run bin/generate_llm_registry and commit the result."

  it "lib/raif/default_llms.rb is current" do
    expect(File.read(Raif::Engine.root.join("lib/raif/default_llms.rb"))).to eq(generator.default_llms_rb(manifest)), hint
  end

  it "lib/raif/default_embedding_models.rb is current" do
    expect(File.read(Raif::Engine.root.join("lib/raif/default_embedding_models.rb"))).to eq(generator.default_embedding_models_rb(manifest)), hint
  end

  it "en.yml model name sections are current" do
    content = File.read(Raif::Engine.root.join("config/locales/en.yml"))
    expect(content).to include(generator.model_names_yaml_block(manifest)), hint
    expect(content).to include(generator.embedding_model_names_yaml_block(manifest)), hint
  end

  it "initializer template key list is current" do
    content = File.read(Raif::Engine.root.join("lib/generators/raif/install/templates/initializer.rb"))
    expect(content).to include(generator.initializer_keys_block(manifest)), hint
  end

  it "setup.md key lists are current" do
    content = File.read(Raif::Engine.root.join("docs/_getting_started/setup.md"))
    %w[open_ai open_ai_responses anthropic bedrock open_router google x_ai embeddings].each do |section|
      expect(content).to include(generator.setup_md_keys_block(manifest, section)), "#{hint} (section: #{section})"
    end
  end

  it "the loaded runtime registry matches RegistryData" do
    expected = Raif::ModelManifest::RegistryData.llm_configs(manifest)
    actual = Raif.default_llms.transform_keys(&:name)
    expect(actual.keys).to eq(expected.keys)
    actual.each do |adapter, configs|
      configs.zip(expected.fetch(adapter)).each do |a, e|
        expect(a[:key]).to eq(e[:key])
        expect(a[:input_token_cost]).to be_within(1e-12).of(e[:input_token_cost])
      end
    end
  end
end
```

- [ ] **Step 2: Run it (should pass immediately); prove it catches staleness** by hand-editing one price in `model_manifest/anthropic.yml`, seeing it fail, reverting the edit, seeing it pass.

Run: `bundle exec rspec spec/lib/raif/generated_artifacts_spec.rb`

- [ ] **Step 3: Commit**

```bash
git add spec/lib/raif/generated_artifacts_spec.rb
git commit -m "Add freshness spec for generated registry artifacts"
```

---

### Task 8: Delete migration scaffolding

**Files:**
- Delete: `script/extract_model_manifest.rb`, `spec/lib/raif/registry_equivalence_spec.rb`, `spec/fixtures/registry_equivalence/`

- [ ] **Step 1: Delete, run the full suite, commit**

```bash
git rm script/extract_model_manifest.rb spec/lib/raif/registry_equivalence_spec.rb
git rm -r spec/fixtures/registry_equivalence
bundle exec rspec
git commit -m "Remove one-time registry migration scaffolding"
```

---

### Task 9: Smoke runner core (selection, credentials, policy)

Logic lives in `script/smoke/` as plain requireable Ruby so specs can unit-test it without live APIs.

**Files:**
- Create: `script/smoke/selection.rb`, `script/smoke/credentials.rb`, `script/smoke/policy.rb`
- Test: `spec/script/smoke/selection_spec.rb`, `spec/script/smoke/policy_spec.rb`

**Interfaces:**
- Consumes: `Raif::ModelManifest` entries.
- Produces:
  - `Smoke::Selection.resolve(argv_selectors, entries, stale_days: nil)` returns `{ entries: [Entry], explicit_keys: [String], unknown: [String] }`. Selector grammar: exact key = explicit; `ALL` / provider prefix (`anthropic`, `open_ai`, `open_ai_responses`, `bedrock`, `open_router`, `google`, `x_ai`, `embeddings`) / `--stale N` = pattern. Retired entries are never selected.
  - `Smoke::Credentials.missing_for?(provider_name)` and `Smoke::Credentials.configure_raif!` (port verbatim from `script/smoke_llm_models.rb:92-189`: the env-to-config block, `provider_for_model_key`, `bedrock_credentials_present?`, instructions text)
  - `Smoke::Policy.exit_code(results, explicit_keys:, strict: false)` returns 0/1. Nonzero when any explicitly selected model (or any model, when `strict`) has a FAIL, TIMEOUT, SKIP, or unexecuted required check. Pattern selections tolerate credential SKIPs.
  - `Smoke::Policy.recordable?(model_result, explicit_keys:)` returns false for a capability result of skip/timeout on an explicitly selected model (spec rule: `--record` must not stamp them fresh)
  - Result shapes: `model_result = { key: String, explicit: bool, capabilities: { "completion" => { status: :pass|:fail|:skip|:timeout|:note, detail: String }, ... } }`

- [ ] **Step 1: Write failing specs for Selection and Policy** using the Task 1 fixture manifest. Cover: provider prefix selection; explicit key selection marks `explicit_keys`; `ALL` excludes retired; unknown selector reported; policy exit codes for the four statuses under explicit vs pattern vs strict; `recordable?` false for skip/timeout on explicit keys, true for pass/fail.

- [ ] **Step 2: Implement the three files.** `selection.rb` generalizes the SELECTORS hash from `script/smoke_llm_models.rb:9-17` (keep the same provider names, add `embeddings`). `credentials.rb` is a verbatim port into a module (single copy replacing the four duplicated ones). `policy.rb` is new, small, pure.

- [ ] **Step 3: Run specs until green, commit**

```bash
bundle exec rspec spec/script/smoke
git add script/smoke/ spec/script/smoke/
git commit -m "Add smoke runner selection, credentials, and result policy modules"
```

---

### Task 10: Smoke checks

**Files:**
- Create: `script/smoke/checks.rb`
- Create: `spec/fixtures/smoke/nonce.png`, `spec/fixtures/smoke/nonce.pdf` (both containing the rendered text `RAIF-SMOKE-7391`)
- Test: `spec/script/smoke/checks_spec.rb` (matrix derivation only; the live calls are not unit-tested)

**Interfaces:**
- Consumes: `Entry#smokable_capabilities`, `Entry#claimed_value`, `Raif.llm`, `Raif.llm_config`.
- Produces: `Smoke::Checks.run_for(entry, only: nil, skip: [], iterations: 1, batch_timeout: 600)` returns the `capabilities` hash of the model_result shape from Task 9. `Smoke::Checks::NONCE = "RAIF-SMOKE-7391"`.

**Check implementations** (each rescues StandardError to `{ status: :fail, detail: "#{e.class}: #{e.message.to_s.first(180)}" }`):

- `completion`: `llm.chat(message: "Reply with exactly: ok")`; pass when `raw_response.to_s.downcase.include?("ok")`.
- `temperature`: when claimed true: `llm.chat(message: "Reply with exactly: ok", temperature: 0.2)`; pass on any successful response. When claimed false: rebuild the llm with the setting force-enabled and probe; a success reports `{ status: :note, detail: "claimed unsupported but appears to work" }`, an API error reports `:pass` (claim confirmed):

```ruby
config = Raif.llm_config(entry.key)
forced = config[:llm_class].new(
  **config.except(:llm_class).merge(
    model_provider_settings: (config[:model_provider_settings] || {}).merge(supports_temperature: true)
  )
)
forced.chat(message: "Reply with exactly: ok", temperature: 0.2)
```

- `structured_outputs`: port the probe body from `script/probe_structured_outputs.rb:212-277` (the `ProbeStructuredOutputsTask` class, JSON parse, key/type assertions, and the `response_format_parameter` readout). Result: `:pass` with detail `"native"` or `"json_response_tool"`; claimed-false direction probes with `supports_structured_outputs: true` forced (same rebuild pattern as temperature) and reports `:note` when native structured outputs succeed.
- `native_tool_use`: `llm.chat(message: "Use the wikipedia_search tool to look up the current Prime Minister of Canada.", available_model_tools: [Raif::ModelTools::WikipediaSearch], tool_choice: "wikipedia_search")`; pass when `response_tool_calls&.first&.dig("arguments").is_a?(Hash)` (covers forced tool choice by construction).
- `streaming`: run `llm.chat(message: "Reply with exactly: ok") { |_mc, _delta, _event| deltas += 1 }` and the same unstreamed; pass when both succeed, the streamed response text contains "ok", and `deltas > 0`. Clear the fallback first, restoring after: `Raif.config.streaming_unsupported_model_keys = []` (see `script/probe_streaming_tool_calls.rb:100`).
- `streaming_tool_calls`: port `classify` and the paired streamed/unstreamed tool-call runs from `script/probe_streaming_tool_calls.rb:132-152`; run `iterations` times per path (default 1 in matrix runs); pass when every streamed iteration classifies `:ok`.
- `batch_inference`: confirm terminal status names first (`grep -n "STATUSES" app/models/raif/model_completion_batch.rb`), then:

```ruby
batch = llm.create_batch
2.times do |i|
  llm.build_pending_model_completion(
    messages: [{ "role" => "user", "content" => "Reply with exactly: ok" }],
    raif_model_completion_batch: batch,
    batch_custom_id: "smoke-#{i}"
  )
end
llm.submit_batch!(batch)
deadline = Time.now + batch_timeout
loop do
  status = llm.fetch_batch_status!(batch)
  break if %w[completed failed cancelled expired].include?(status.to_s) # adjust to actual STATUSES
  return { status: :timeout, detail: "still #{status} after #{batch_timeout}s" } if Time.now > deadline
  sleep 15
end
llm.fetch_batch_results!(batch)
ok = batch.raif_model_completions.reload.all? { |mc| mc.raw_response.to_s.downcase.include?("ok") }
{ status: ok ? :pass : :fail, detail: "batch #{batch.status}" }
```

(If `create_batch` validation requires a creator, pass `creator: Raif::TestUser.first || Raif::TestUser.create!(email: "smoke@example.invalid")`.)
- `images`: `llm.chat(messages: [{ role: "user", content: ["What text appears in this image? Reply with only that text.", Raif::ModelImageInput.new(input: "spec/fixtures/smoke/nonce.png")] }])`; pass when the response contains `NONCE`.
- `pdfs`: same with `Raif::ModelFileInput.new(input: "spec/fixtures/smoke/nonce.pdf")`.
- `provider_managed_tools`: for each declared tool name, one cheap invocation; for `web_search`: `llm.chat(message: "Search the web for the current year and reply with it.", available_model_tools: [Raif::ModelTools::ProviderManaged::WebSearch])`, pass on any successful completion; `code_execution` prompt: "Use code execution to compute 7 * 6 and reply with the result." pass when response contains "42"; `image_generation`: skip with detail "not smoked (expensive)" and status `:skip` unless `--only provider_managed_tools`.

- [ ] **Step 1: Create the fixtures**

```bash
mkdir -p spec/fixtures/smoke
magick -size 400x80 -background white -fill black -pointsize 32 label:RAIF-SMOKE-7391 spec/fixtures/smoke/nonce.png
```

(If ImageMagick is unavailable: `brew install imagemagick`, or render the text any other way; the only requirement is legible `RAIF-SMOKE-7391` on a plain background.)

For the PDF, write this minimal valid PDF by hand to `spec/fixtures/smoke/nonce.pdf` (Ruby heredoc in a throwaway one-liner, byte offsets in the xref do not need to be exact for modern readers, but generate it properly):

```bash
bundle exec ruby -e '
content = "BT /F1 24 Tf 72 720 Td (RAIF-SMOKE-7391) Tj ET"
pdf = +"%PDF-1.4\n"
objs = []
objs << "1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n"
objs << "2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n"
objs << "3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >> endobj\n"
objs << "4 0 obj << /Length #{content.bytesize} >> stream\n#{content}\nendstream endobj\n"
objs << "5 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj\n"
offsets = []
objs.each { |o| offsets << pdf.bytesize; pdf << o }
xref = pdf.bytesize
pdf << "xref\n0 6\n0000000000 65535 f \n"
offsets.each { |off| pdf << format("%010d 00000 n \n", off) }
pdf << "trailer << /Size 6 /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n"
File.binwrite("spec/fixtures/smoke/nonce.pdf", pdf)
'
```

Verify both open (Preview/`qlmanage -p`).

- [ ] **Step 2: Write the matrix-derivation spec** (`checks_spec.rb`): with a fixture entry, `Smoke::Checks.run_for(entry, only: "streaming")` invokes only the streaming check; `skip: ["batch_inference"]` yields `{ status: :skip }` for it; claimed-false cheap capabilities (temperature, structured_outputs) are probed while claimed-false expensive ones (batch, images) are not. Stub the live-call methods (`Raif.llm`) with instance_doubles; assert dispatch, not API behavior.

- [ ] **Step 3: Implement `script/smoke/checks.rb`**, run the spec until green.

- [ ] **Step 4: Commit**

```bash
git add script/smoke/checks.rb spec/script/smoke/checks_spec.rb spec/fixtures/smoke/
git commit -m "Add capability check implementations for the smoke runner"
```

---

### Task 11: Recorder

**Files:**
- Create: `script/smoke/recorder.rb`
- Test: `spec/script/smoke/recorder_spec.rb`

**Interfaces:**
- Consumes: Entry (`source_path`, `key_base`, `endpoint`), Task 9 result shapes, `Smoke::Policy.recordable?`.
- Produces: `Smoke::Recorder.record!(entry, capability_results, ran_full_unskipped:, now: Time.now.utc)`: loads `entry.source_path` YAML, locates the model node (by `key` or, for open_ai, `key_base` + `endpoints[entry.endpoint]`), merges per-capability records `{ "claimed" => <claim at run time>, "result" => <status/detail string>, "checked_at" => now.iso8601 }` for every recordable capability result, sets `last_full_run_at` only when `ran_full_unskipped` is true, writes the file back with `to_yaml`.
- Result strings: `pass`, `pass_native`, `pass_json_tool` (structured outputs uses the detail), `fail`, `timeout`, `note_works_despite_claim`. Skips are never written.

- [ ] **Step 1: Write failing recorder specs** against a tmpdir copy of the fixture manifest: records results for a plain provider entry and an open_ai endpoint entry; skip results not written; `last_full_run_at` written only on full runs; a second `Raif::ModelManifest.load` round-trips the written values; file remains valid per the Task 3 validity rules (re-run the validation assertions on the written file).

- [ ] **Step 2: Implement, run until green, commit**

```bash
git add script/smoke/recorder.rb spec/script/smoke/recorder_spec.rb
git commit -m "Add smoke result recorder writing verification blocks to the manifest"
```

---

### Task 12: `bin/smoke` CLI, old script removal, CONTRIBUTING rewrite

**Files:**
- Create: `script/smoke.rb`, `bin/smoke`
- Delete: `bin/smoke_llm_models`, `script/smoke_llm_models.rb`, `bin/smoke_embedding_models`, `script/smoke_embedding_models.rb`, `bin/probe_structured_outputs`, `script/probe_structured_outputs.rb`, `bin/probe_streaming_tool_calls`, `script/probe_streaming_tool_calls.rb`, `bin/probe_bedrock_stream_transport`, `script/probe_bedrock_stream_transport.rb`
- Modify: `CONTRIBUTING.md:47-66` (replace the smoke section)

**Interfaces:**
- Consumes: everything from Tasks 9-11.
- Produces: the CLI contract from the spec:

```
bin/smoke <selectors...> [--only CAP[,CAP]] [--skip CAP[,CAP]] [--stale DAYS]
          [--record] [--strict] [--format text|json] [--iterations N]
          [--batch-timeout SECONDS] [--list]
```

- [ ] **Step 1: Implement `script/smoke.rb`**: OptionParser for the flags above; `Smoke::Credentials.configure_raif!`; `Smoke::Selection.resolve`; per provider thread (`entries.group_by(&:provider_name)`, `Thread.new` per group, models sequential within), each model: credential check (skip per policy) then `Smoke::Checks.run_for`; embeddings selector runs the embedding check (`Raif.embedding_model(key).generate_embedding!("hello smoke")` asserting vector size). Output: text matrix (one row per model, one column per capability, statuses as PASS/FAIL/SKIP/TIMEOUT/NOTE) or `--format json` (`JSON.pretty_generate` of the model_result array). With `--record`: call `Smoke::Recorder.record!` per model with `ran_full_unskipped` computed from options. Exit via `Smoke::Policy.exit_code`.

- [ ] **Step 2: Create `bin/smoke`** (copy `bin/smoke_llm_models` wrapper shape, point at `script/smoke.rb`, `chmod +x`), delete the five old script pairs (`git rm`).

- [ ] **Step 3: Rewrite the CONTRIBUTING.md smoke section**

```markdown
### Manual LLM Smoke Tests

`bin/smoke` verifies live models against the capabilities claimed in `model_manifest/*.yml`:

```bash
bin/smoke anthropic_claude_5_sonnet          # one model, full capability matrix
bin/smoke anthropic bedrock                  # provider sweeps
bin/smoke --all                              # everything with credentials available
bin/smoke --stale 30                         # models with unverified or stale capabilities
bin/smoke x_ai --only batch_inference        # one capability
bin/smoke bedrock_claude_5_sonnet --only streaming_tool_calls --iterations 5
bin/smoke anthropic_claude_5_sonnet --record # write results back to the manifest
```

Notes:
- Explicitly selected models fail (nonzero exit) on SKIP or TIMEOUT; provider sweeps skip providers without credentials.
- Credentials: ANTHROPIC_API_KEY, OPENAI_API_KEY, OPEN_ROUTER_API_KEY (or OPENROUTER_API_KEY), GOOGLE_AI_API_KEY (or GOOGLE_API_KEY), XAI_API_KEY (or X_AI_API_KEY), AWS credentials plus AWS_REGION for Bedrock.
- `--record` updates the verification blocks in model_manifest/; commit those changes.
- `bin/smoke --list` prints all model keys. `--format json` emits machine-readable results.
```

- [ ] **Step 4: Live sanity run** (needs at least one provider key in the environment):

```bash
bin/smoke anthropic_claude_4_5_haiku --skip batch_inference
```

Expected: matrix output with PASS rows for completion/streaming/tool use/structured outputs/images/pdfs. Investigate any FAIL before proceeding (a seeded capability may be wrong; fix the manifest, `bin/generate_llm_registry`, re-run).

- [ ] **Step 5: Full suite + commit**

```bash
bundle exec rspec
git add -A script/ bin/ CONTRIBUTING.md
git commit -m "Replace per-capability smoke and probe scripts with unified bin/smoke"
```

---

### Task 13: Runtime deprecation support

**Files:**
- Modify: `app/models/raif/llm.rb:8-48` (attributes + initialize + deprecation_message)
- Modify: `lib/raif/llm_registry.rb:19-28` (warning in `Raif.llm`)
- Modify: `lib/raif/configuration.rb:237-240` (boot warning after the default-key existence check)
- Test: `spec/models/raif/llm_spec.rb` (new describe block), `spec/lib/raif/configuration_spec.rb` or wherever `validate!` is specced (`grep -rln "validate!" spec/`)

**Interfaces:**
- Produces: `Raif::Llm#deprecated?`, `#retirement_date`, `#replacement_key`, `#migration_note`, `#deprecation_message`; `Raif.llm` logs the message once per process per key; `Raif.reset_deprecation_warnings!` (test hook).

- [ ] **Step 1: Write failing specs**

```ruby
describe "deprecation" do
  let(:llm) do
    Raif::Llms::TestLlm.new(
      key: :raif_test_llm, api_name: "raif-test-llm",
      deprecated: true, retirement_date: Date.new(2026, 12, 1),
      replacement_key: :anthropic_claude_5_sonnet
    )
  end

  it "builds the full message with a replacement" do
    expect(llm.deprecation_message).to eq(
      "Raif model :raif_test_llm is deprecated and will be removed after 2026-12-01. Use :anthropic_claude_5_sonnet instead."
    )
  end

  it "uses the migration note when there is no replacement" do
    llm = Raif::Llms::TestLlm.new(
      key: :raif_test_llm, api_name: "raif-test-llm",
      deprecated: true, retirement_date: Date.new(2026, 12, 1),
      migration_note: "No direct replacement."
    )
    expect(llm.deprecation_message).to eq(
      "Raif model :raif_test_llm is deprecated and will be removed after 2026-12-01. No direct replacement."
    )
  end

  it "warns once per process per key when instantiated through Raif.llm" do
    Raif.register_llm(Raif::Llms::TestLlm, key: :deprecated_test_llm, api_name: "dep-test",
      deprecated: true, retirement_date: Date.new(2026, 12, 1))
    Raif.reset_deprecation_warnings!
    expect(Raif.logger).to receive(:warn).with(/deprecated_test_llm is deprecated/).once
    2.times { Raif.llm(:deprecated_test_llm) }
  ensure
    Raif.llm_registry.delete(:deprecated_test_llm)
  end

  it "does not warn for active models" do
    Raif.reset_deprecation_warnings!
    expect(Raif.logger).not_to receive(:warn)
    Raif.llm(:raif_test_llm)
  end
end
```

- [ ] **Step 2: Implement.** In `Llm`: add `:deprecated, :retirement_date, :replacement_key, :migration_note` to `attr_accessor`; add the four kwargs (defaults `deprecated: false`, rest `nil`) to `initialize` and assign; add:

```ruby
    def deprecated?
      !!deprecated
    end

    def deprecation_message
      message = +"Raif model :#{key} is deprecated"
      message << " and will be removed after #{retirement_date}" if retirement_date
      message << "."
      if replacement_key
        message << " Use :#{replacement_key} instead."
      elsif migration_note
        message << " #{migration_note}"
      end
      message
    end
```

In `lib/raif/llm_registry.rb`, inside `Raif.llm` after instantiation:

```ruby
    llm = llm_class.new(**llm_config.except(:llm_class))
    warn_if_deprecated(llm)
    llm
  end

  def self.warn_if_deprecated(llm)
    return unless llm.deprecated?

    @deprecation_warnings_issued ||= {}
    return if @deprecation_warnings_issued[llm.key]

    @deprecation_warnings_issued[llm.key] = true
    Raif.logger.warn(llm.deprecation_message)
  end

  def self.reset_deprecation_warnings!
    @deprecation_warnings_issued = {}
  end
```

In `configuration.rb` `validate!`, immediately after the default-key existence check at line 240:

```ruby
      default_llm_config = Raif.llm_config(default_llm_model_key.to_sym)
      if default_llm_config && default_llm_config[:deprecated]
        Raif.logger.warn(
          "Raif.config.default_llm_model_key is set to :#{default_llm_model_key}, which is deprecated" \
            "#{default_llm_config[:retirement_date] ? " and will be removed after #{default_llm_config[:retirement_date]}" : ""}." \
            "#{default_llm_config[:replacement_key] ? " Use :#{default_llm_config[:replacement_key]} instead." : ""}"
        )
      end
```

Add a spec for the boot warning next to the existing `validate!` specs (register a deprecated test llm, set it as default, expect the warn, restore).

- [ ] **Step 3: Run new specs, then full suite; commit**

```bash
bundle exec rspec spec/models/raif/llm_spec.rb
bundle exec rspec
git add -A app/models/raif/llm.rb lib/raif/llm_registry.rb lib/raif/configuration.rb spec/
git commit -m "Add runtime deprecation warnings for deprecated models"
```

---

### Task 14: Admin badge

**Files:**
- Modify: `app/views/raif/admin/llms/index.html.erb:73` (name cell)
- Modify: `config/locales/en.yml` (admin section; find with `grep -n "admin:" config/locales/en.yml` and add under `raif.admin.llms.index`)
- Test: the admin llms request/system spec (`grep -rln "admin/llms\|admin_llms" spec/` to find it)

- [ ] **Step 1: Failing spec**: register a deprecated test llm (as in Task 13), hit the admin llms index, expect the response body to include "Deprecated". Follow whatever pattern the existing admin llms spec uses.

- [ ] **Step 2: Implement.** Name cell becomes:

```erb
                  <td>
                    <%= llm.name %>
                    <% if llm.deprecated? %>
                      <span class="badge bg-warning text-dark ms-1" title="<%= llm.deprecation_message %>">
                        <%= t("raif.admin.llms.index.deprecated_badge") %><%= " (until #{llm.retirement_date})" if llm.retirement_date %>
                      </span>
                    <% end %>
                  </td>
```

Locale addition (alphabetical position within the existing `raif.admin.llms.index` keys): `deprecated_badge: Deprecated`.

Note: this view iterates `@llms`; check how the controller builds them (`grep -n "@llms" app/controllers/raif/admin/llms_controller.rb`). If it builds config hashes rather than `Raif::Llm` instances, adapt the badge condition to the actual object.

- [ ] **Step 3: Run the admin spec, `bin/lint` (i18n-tasks), full suite; commit**

```bash
git add app/views/raif/admin/llms/index.html.erb config/locales/en.yml spec/
git commit -m "Badge deprecated models in the admin LLMs index"
```

---

### Task 15: Claude command files

**Files:**
- Create: `.claude/commands/model-check.md`, `.claude/commands/model-add.md`, `.claude/commands/model-retire.md`

No tests; these are prose instructions. Follow the file shape of `.claude/commands/release-prep.md` (frontmatter-less markdown addressed to Claude).

- [ ] **Step 1: Write `.claude/commands/model-check.md`**

```markdown
# Model Check

Patrol raif's model registry for drift against provider reality. Arguments (optional): a provider name, a concern ("pricing openai"), a URL, or a free-text tip. With no arguments, ask first: "Anything specific that prompted this, or general sweep?"

Rules that apply to every step:
- Research first, report second, act only after explicit approval. Never edit files before the user picks items to act on.
- One PR-sized branch per concern. NEVER push or open a PR without explicit approval of that specific branch.
- No em dashes or en dashes in anything you write (CHANGELOG, commits, docs). No AI attribution in commits. Keep wording generic to raif.

Steps:
1. Read `model_manifest/*.yml`. Note each provider's `references` URLs.
2. Gather, scoped by the user's hint when given: fetch the reference URLs (WebFetch), search the web for announcements since the newest `added_on`, and where a provider has a public list-models API and a key is configured, list it (OpenAI GET /v1/models, Anthropic GET /v1/models, xAI GET /v1/models, OpenRouter GET /api/v1/models, Google GET /v1beta/models).
3. Cross-reference against the manifest and report findings in these groups, each item with its source cited:
   - models available upstream but absent from the manifest
   - pricing differences (manifest per-million vs published)
   - announced deprecations or retirements not recorded in lifecycle fields
   - recorded retirement_dates within 60 days or past
   - deprecated models whose replacement_key is itself deprecated, or with neither replacement_key nor migration_note
   - models with unverified or stale capabilities (run `bin/smoke --stale 30 --list`-equivalent by checking verification blocks; do not hit live APIs for this)
4. Ask which findings to act on (AskUserQuestion, multiSelect).
5. For each approved finding, ask: handle here sequentially, or write a handoff doc per concern to `docs/handoffs/` (Goal / Current State / Key Decisions / Next Steps format) for parallel sessions.
6. Acting on a finding in-session:
   - pricing update: edit the manifest pricing, run `bin/generate_llm_registry`, run `bundle exec rspec spec/lib/raif/model_manifest_validity_spec.rb spec/lib/raif/generated_artifacts_spec.rb`, add a CHANGELOG bullet, commit on a `model-pricing-<provider>` branch
   - new model: switch to the /model-add workflow with what you learned
   - deprecation/retirement: switch to the /model-retire workflow
   - if the user supplied a URL that proved useful, add it to that provider's `references` in the manifest
```

- [ ] **Step 2: Write `.claude/commands/model-add.md`**

```markdown
# Model Add

Add one new model to raif, end to end. Argument: a model name, provider + name, or an announcement URL.

Rules: research first and confirm before editing; the smoke gate is mandatory and cannot be skipped; NEVER push or open a PR without explicit approval; no em or en dashes anywhere; no AI attribution in commits.

Steps:
1. Research the model from the argument plus the provider's `references` URLs in `model_manifest/<provider>.yml`: API name, per-million pricing, max output tokens, capabilities (temperature parameter support, structured outputs, tool calling, streaming, batch API availability, image/PDF input, provider-managed tools).
2. Propose a complete manifest entry in chat: every field, with a source citation per fact and every unverifiable guess flagged as a guess (for example "no batch API documented, claiming batch_inference: false"). For OpenAI models, propose both endpoints (or responses-only). Ask for approval.
3. On approval:
   - branch: `git checkout -b model-add-<key>` from main
   - add the entry to `model_manifest/<provider>.yml` (status: active, added_on: today, display_name following the existing naming pattern for that provider)
   - run `bin/generate_llm_registry`
   - run `bundle exec rspec spec/lib/raif/model_manifest_validity_spec.rb spec/lib/raif/generated_artifacts_spec.rb spec/models/raif/llm_spec.rb`
4. Smoke it (mandatory): `bin/smoke <key> --record`. Requires credentials for the provider; if they are missing, stop and ask the user to provide them. Do not proceed on SKIP or TIMEOUT.
5. Present the smoke matrix. For each discrepancy (claimed true but failed, or NOTE that a claimed-false capability works): propose the manifest correction, apply on approval, regenerate, re-smoke the affected capability with `bin/smoke <key> --only <capability> --record`. Loop until the matrix matches the claims.
6. Add a CHANGELOG bullet under the current pre-release heading: "Added <display_name> (`<key>`)" plus notable capability caveats. Run `bundle exec rspec` and `bin/lint`.
7. Commit. Show the user the full diff and the smoke matrix, then STOP. Push and PR only after they approve (PR body includes the smoke matrix as evidence).
```

- [ ] **Step 3: Write `.claude/commands/model-retire.md`**

```markdown
# Model Retire

Deprecate or remove a model. Argument: a model key, optionally with a provider announcement URL.

Rules: confirm the provider's announcement before editing; NEVER push or open a PR without explicit approval; no em or en dashes; no AI attribution in commits.

Decide the mode first:
- Provider announced end of life but the model still works: DEPRECATE.
- Retirement date reached or the API already rejects it: REMOVE.
Confirm the mode with the user.

DEPRECATE:
1. Verify the announcement (fetch the provider's deprecations URL from the manifest references; cite it).
2. Set lifecycle on the manifest entry: status: deprecated, deprecated_on, retirement_date, and replacement_key (must be an active key). When the provider names no successor, ask the user: propose the closest alternative with caveats stated, or set migration_note explaining there is no direct replacement.
3. `bin/generate_llm_registry`, then `bundle exec rspec`.
4. CHANGELOG bullet: "Deprecated `<key>`; scheduled for removal after <retirement_date>. <replacement or note>."
5. Branch `model-deprecate-<key>`, commit, show the diff, STOP for review.

REMOVE:
1. Set status: retired on the manifest entry (keep all lifecycle history; never delete the entry).
2. `bin/generate_llm_registry`.
3. Find residue: `grep -rn "<key>" spec/ lib/ app/ docs/ vcr_cassettes/`. Migrate specs that used the key to the replacement; regenerate or edit affected VCR cassettes the way the repo has done before (see git log for prior removals, for example cec8728d).
4. `bundle exec rspec` and `bin/lint` until green.
5. CHANGELOG bullet prefixed "**Breaking change**:" naming the key, the provider's retirement notice (cite URL), and the replacement guidance.
6. Branch `model-retire-<key>`, commit, show the diff, STOP for review.
```

- [ ] **Step 4: Commit**

```bash
git add .claude/commands/model-check.md .claude/commands/model-add.md .claude/commands/model-retire.md
git commit -m "Add model-check, model-add, and model-retire Claude commands"
```

---

### Task 16: Docs and CHANGELOG

**Files:**
- Modify: `docs/_learn_more/customization.md:136-157` ("Adding LLM Models" section)
- Modify: `CLAUDE.md` (registry pattern section and common pitfalls)
- Modify: `CHANGELOG.md` (current `## v1.6.0-pre` section)

- [ ] **Step 1: Update customization.md.** The "Adding LLM Models" host-app instructions (`Raif.register_llm` at runtime) remain valid for HOST apps; add a paragraph distinguishing contribution: models shipped with raif are defined in `model_manifest/*.yml` and regenerated with `bin/generate_llm_registry`; contributors edit the manifest, never `lib/raif/default_llms.rb`. Mention `model_provider_settings` and `supported_provider_managed_tools` in the host-app example (the current example shows only key/api_name/costs).

- [ ] **Step 2: Update CLAUDE.md.** In the registry pattern section add: "Model definitions live in `model_manifest/*.yml`; `bin/generate_llm_registry` regenerates `lib/raif/default_llms.rb`, locale names, the initializer template, and setup docs. Never edit generated files directly." In common pitfalls add: "Editing `lib/raif/default_llms.rb` or the en.yml model_names section by hand will fail the freshness spec; edit `model_manifest/` and regenerate. Smoke models with `bin/smoke <key> --record`."

- [ ] **Step 3: CHANGELOG bullets** (under `## v1.6.0-pre`, matching the existing verbose prose style, no em dashes):

```markdown
- Model definitions are now driven by a machine readable manifest (`model_manifest/*.yml`) that records each model's pricing, capabilities, lifecycle status, and last verified smoke results. The runtime registry (`lib/raif/default_llms.rb`), the model name locale entries, the install generator's key list, and the setup documentation are all generated from the manifest via `bin/generate_llm_registry`, with a spec that fails when they drift. Registered model keys, pricing, and behavior are unchanged.
- Added deprecation support for built in models. A model marked as deprecated in the manifest logs a one time warning when used (including the scheduled removal date and the suggested replacement), a warning is logged at boot when `Raif.config.default_llm_model_key` points at a deprecated model, and the admin LLMs index badges deprecated models.
- Replaced `bin/smoke_llm_models`, `bin/smoke_embedding_models`, `bin/probe_structured_outputs`, `bin/probe_streaming_tool_calls`, and `bin/probe_bedrock_stream_transport` with a single `bin/smoke` runner that tests each model against the capabilities the manifest claims for it (completion, temperature, structured outputs, tool calling, streaming, streaming tool calls, batch inference, image and PDF inputs, and provider managed tools) and can record verified results back into the manifest with `--record`.
- **Behavior Change**: The default for `Raif.config.streaming_unsupported_model_keys` is now generated from the manifest as an explicit list of model keys (currently `bedrock_gpt_oss_120b` and `bedrock_gpt_oss_20b`) instead of a regex. The effective default behavior is unchanged.
```

- [ ] **Step 4: Full suite + lint + commit**

```bash
bundle exec rspec && bin/lint
git add docs/_learn_more/customization.md CLAUDE.md CHANGELOG.md
git commit -m "Document the model manifest workflow and update the changelog"
```

---

### Task 17: Final verification (do not push)

- [ ] **Step 1: Clean-tree generator idempotence**

```bash
bin/generate_llm_registry && git status --porcelain
```

Expected: empty output (no changes on a fresh run).

- [ ] **Step 2: Full suite and lint one last time**

```bash
bundle exec rspec
bin/lint
```

- [ ] **Step 3: Seed verification data (optional, needs credentials, costs a few dollars)**

```bash
bin/smoke --all --record --skip batch_inference
```

Review NOTE/FAIL rows: each is either a wrong seeded claim (fix manifest, regenerate, re-smoke that capability) or a real provider issue (record it; that is the system working). Commit the verification updates:

```bash
git add model_manifest/
git commit -m "Record initial smoke verification results"
```

- [ ] **Step 4: STOP.** Present the branch summary (`git log --oneline main..HEAD`, `git diff --stat main`) to the user for review. Do not push; do not open a PR. The user decides what happens next.
