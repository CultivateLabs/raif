# Ruby Model Manifest and Trustworthy Smoke Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make smoke verdicts truthful and evidence-based, move live smoke observations out of the manifest into a machine-owned store, and then replace the YAML model manifest with a constrained Ruby DSL.

**Architecture:** The work lands in two phases. Phase A (Tasks 1-6) fixes the smoke trust problems while the manifests are still YAML: claim-aware verdicts, hard oracles, CLI validation, a separate read-only observation store under `model_smoke_results/`, a post-run recorder that never touches manifest source, and `--stale` selection driven by observations instead of embedded verification. Phase B (Tasks 7-9) migrates the manifest format: a constrained Ruby DSL under `model_manifest/*.rb`, a normalized YAML-vs-Ruby equivalence check, and exact generated-artifact freshness. Tasks 10-12 update commands, documentation, and run full verification. Every phase boundary leaves the focused smoke suite green.

**Tech Stack:** Ruby 3.4, Rails 8.1, RSpec, JSON, OptionParser, existing Raif model adapters and generator infrastructure.

**Spec:** `docs/superpowers/specs/2026-08-18-model-lifecycle-design.md` (amended by Task 11 to reflect this design).

## Global Constraints

- Do NOT run `git commit` during implementation. The maintainer applies commits afterwards with the commit-workflow skill. A "Suggested commit plan" section at the end maps tasks to commits.
- Do NOT run `bin/smoke --record` against live APIs at any point during implementation. Until Task 5 completes, `--record` still rewrites manifest source files.
- No em dashes or en dashes anywhere: changelog entries, code comments, commit message suggestions. Use plain punctuation.
- Use `/Users/brian/.asdf/shims/bundle` if a bare `bundle` resolves to a wrong binstub (a host-app `bin/bundle` can shadow PATH).
- Never edit generated files directly: `lib/raif/default_llms.rb`, `lib/raif/default_embedding_models.rb`, the generated regions of `config/locales/en.yml`, `lib/generators/raif/install/templates/initializer.rb`, `docs/_getting_started/setup.md`. Regenerate with `bin/generate_llm_registry`.
- Manifest files must spell out every capability per model. No shared capability hashes, no computed defaults.
- Provider documentation plus user approval determines manifest truth. Smoke results are runtime evidence only. Nothing in this plan may auto-edit a declared capability or auto-delete a stored observation because of a failure.
- The Ruby DSL reduces accidental capabilities (stray Kernel calls, requires, global mutation in manifest files). It is not a security sandbox and must not be described as one.

---

## File map

### Phase A: smoke trust (manifests still YAML)

- Modify `script/smoke/checks.rb`: claim-aware verdict conversion, hard oracles, provider-managed tool evidence, no vacuous passes.
- Modify `spec/script/smoke/checks_spec.rb`: verdict matrix and oracle regressions.
- Modify `script/smoke.rb`: numeric option validation; post-run observation recording; observation-aware selection wiring; terminology.
- Modify `script/smoke/policy.rb`: recordability requires a recordable capability, a `:pass` status, and no `recordable: false` flag.
- Modify `spec/script/smoke/policy_spec.rb`.
- Create `lib/raif/model_manifest/smoke_observations.rb`: read-only observation store plus the single `RECORDABLE_POSITIVE_CAPABILITIES` constant and candidate derivation.
- Create `spec/lib/raif/model_manifest/smoke_observations_spec.rb`.
- Create `spec/fixtures/model_smoke_results/anthropic.json` (test fixture only; the real store starts empty).
- Create `model_smoke_results/.gitkeep` (the committed store starts empty; there is no verification history to migrate).
- Delete `script/smoke/recorder.rb` and `spec/script/smoke/recorder_spec.rb`.
- Create `script/smoke/observation_recorder.rb` and `spec/script/smoke/observation_recorder_spec.rb`.
- Modify `script/smoke/selection.rb`: `--stale` reads the observation store.
- Modify `spec/script/smoke/selection_spec.rb`.
- Modify `lib/raif/model_manifest.rb`: drop `verification` from `Entry`/`EmbeddingEntry`, remove `Entry#unverified_capabilities` (still YAML loading in this phase).
- Modify `spec/lib/raif/model_manifest_spec.rb`.

### Phase B: Ruby manifest migration

- Create `lib/raif/model_manifest/dsl.rb`: constrained builders for provider, model, endpoint, lifecycle, and embedding declarations.
- Modify `lib/raif/model_manifest.rb`: load `.rb` files through an isolated DSL context; normalize entries to symbol-keyed frozen data.
- Replace `model_manifest/*.yml` with `model_manifest/*.rb`.
- Replace `spec/fixtures/model_manifest/*.yml` with `spec/fixtures/model_manifest/*.rb`.
- Modify `spec/lib/raif/model_manifest_spec.rb` and `spec/lib/raif/model_manifest_validity_spec.rb`.
- Create temporary `spec/support/legacy_yaml_manifest.rb` plus a temporary equivalence example; both are deleted within Task 8.
- Modify `lib/raif/model_manifest/registry_data.rb`: symbol-keyed access.
- Modify `lib/raif/model_manifest/generator.rb`: add public whole-file transforms composed from the existing pure primitives (`replace_yaml_section`, `replace_between_markers` already exist and are already used by the write paths; do not restructure them).
- Modify `spec/lib/raif/model_manifest_generator_spec.rb` and `spec/lib/raif/generated_artifacts_spec.rb`: exact whole-file freshness.
- Regenerate `lib/raif/default_llms.rb`, `lib/raif/default_embedding_models.rb`, `config/locales/en.yml`, `lib/generators/raif/install/templates/initializer.rb`, `docs/_getting_started/setup.md`.

### Workflow and documentation

- Modify `.claude/commands/model-add.md`, `.claude/commands/model-check.md`, `.claude/commands/model-retire.md`.
- Modify `CONTRIBUTING.md`, `CLAUDE.md`, `CHANGELOG.md`, `docs/_learn_more/customization.md`, `docs/_learn_more/streaming.md`.
- Amend `docs/superpowers/specs/2026-08-18-model-lifecycle-design.md`.

---

### Task 1: Claim-aware smoke verdicts

**Files:**
- Modify: `script/smoke/checks.rb`
- Test: `spec/script/smoke/checks_spec.rb`

**Interfaces:**
- Consumes: existing `Smoke::Checks.run_for(entry, only:)` returning a hash of capability name to `{ status:, detail: }`; existing `probe_claimed_false_direction` (around `script/smoke/checks.rb:382-393`); manifest entries with string-keyed capabilities (`entry.claimed_value("streaming")` and similar).
- Produces: `Smoke::Checks.verdict_for(claimed:, observed_result:)` applied to every check result before it is returned from `run_for`; claimed-false exceptions surface as `:fail`.

The current behavior has three distinct cases and only one of them is correct:

1. Cheap claimed-false probes (temperature, structured outputs) that unexpectedly succeed already return `:note`. Preserve this.
2. Any `StandardError` inside `probe_claimed_false_direction` currently returns `{ status: :pass, detail: "claim confirmed: ..." }`. This is the dangerous inversion: an auth failure, timeout, or typo confirms the claim. Fix to `:fail`.
3. Expensive checks (streaming, native tool use, streaming tool calls, batch, images, PDFs) run their positive check when explicitly requested via `--only` and ignore the claimed value entirely, so a claimed-false capability that works returns `:pass`. Fix to `:note`.

- [ ] **Step 1: Write the verdict matrix tests**

Add to `spec/script/smoke/checks_spec.rb` a shared set of examples covering all three cases. Use the existing spec's stubbing style for LLM construction; the shape is:

```ruby
describe "claimed-false verdicts" do
  # Case 1 (regression guard, already green): cheap probe success stays :note
  it "reports a working claimed-false temperature probe as :note" do
    result = described_class.run_for(claimed_false_entry, only: "temperature")
    expect(result.fetch("temperature")).to include(
      status: :note,
      detail: include("claimed unsupported but appears to work")
    )
  end

  # Case 2 (currently red): exceptions never confirm a claim
  it "reports an exception during a claimed-false probe as :fail" do
    allow(llm).to receive(:chat).and_raise(Faraday::UnauthorizedError.new("401"))
    result = described_class.run_for(claimed_false_entry, only: "temperature")
    expect(result.fetch("temperature")).to include(status: :fail)
    expect(result.fetch("temperature").fetch(:detail)).not_to include("claim confirmed")
  end

  # Case 3 (currently red): explicitly requested expensive claimed-false success is :note
  it "reports a working explicitly requested claimed-false streaming check as :note" do
    result = described_class.run_for(claimed_false_entry, only: "streaming")
    expect(result.fetch("streaming")).to include(
      status: :note,
      detail: include("claimed unsupported but appears to work")
    )
  end
end
```

Write case 3 examples for each of: native tool use, streaming, streaming tool calls, batch inference, images, PDFs. Write case 2 examples for at least temperature and structured outputs (the probe path) and one expensive check (exception during a claimed-false streaming check returns `:fail`).

- [ ] **Step 2: Run the checks spec and verify the expected failures**

Run:

```bash
bundle exec rspec spec/script/smoke/checks_spec.rb
```

Expected: case 1 examples PASS already (they are regression guards; do not be surprised). Case 2 and case 3 examples FAIL against current behavior. If a case 1 example fails, stop and re-read the current probe code before proceeding.

- [ ] **Step 3: Centralize claim-aware result conversion**

Add to `script/smoke/checks.rb`:

```ruby
def self.verdict_for(claimed:, observed_result:)
  return observed_result if claimed
  return observed_result unless observed_result[:status] == :pass

  observed_result.merge(
    status: :note,
    detail: "claimed unsupported but appears to work: #{observed_result[:detail]}"
  )
end
```

Apply `verdict_for` uniformly in `run_for` to every check result, passing `claimed: entry.claimed_value(capability_name)` (keep the existing string capability names in this phase). Delete the branch of `probe_claimed_false_direction` that rescues `StandardError` and returns `:pass` with "claim confirmed"; an exception during any probe is `{ status: :fail, detail: "<exception class>: <message>" }`. Keep the force-enable behavior that bypasses Raif's local guard for temperature/structured-output probes; API-level rejections then surface as `:fail` observations, which is correct.

- [ ] **Step 4: Run the checks spec and verify it passes**

Run:

```bash
bundle exec rspec spec/script/smoke/checks_spec.rb
```

Expected: all examples pass, including the pre-existing ones.

### Task 2: Strengthen hard oracles

**Files:**
- Modify: `script/smoke/checks.rb`
- Test: `spec/script/smoke/checks_spec.rb`

**Interfaces:**
- Consumes: `Raif::ModelCompletion#provider_managed_tool_calls` (exists at `app/models/raif/concerns/provider_managed_tool_calls.rb`); existing check methods `check_completion`, `check_streaming`, `check_streaming_tool_calls`, `check_batch_inference`, and the provider-managed tool checks around `script/smoke/checks.rb:339-353`.
- Produces: check results that may carry `recordable: false` for diagnostic-only successes (consumed by Task 5's policy); no check passes without concrete evidence.

- [ ] **Step 1: Write failing oracle tests**

Add to `spec/script/smoke/checks_spec.rb`:

```ruby
it "fails completion when the response merely contains 'ok' as a substring" do
  allow(llm).to receive(:chat).and_return(
    instance_double(Raif::ModelCompletion, raw_response: "not okay", response_text: "not okay")
  )
  expect(described_class.check_completion(entry)).to include(status: :fail)
end

it "fails streaming tool calls when iterations is zero" do
  expect(described_class.check_streaming_tool_calls(entry, iterations: 0)).to include(status: :fail)
end

it "fails provider-managed web search without matching tool call evidence" do
  allow(model_completion).to receive(:provider_managed_tool_calls).and_return([])
  expect(check_result_for("provider_managed_tools")).to include(status: :fail)
end

it "passes provider-managed web search with matching tool call evidence" do
  allow(model_completion).to receive(:provider_managed_tool_calls).and_return([
    { "tool_name" => "web_search", "provider_tool_call_id" => "search_1" }
  ])
  expect(check_result_for("provider_managed_tools")).to include(status: :pass)
end
```

Cover web search, code execution, and image generation: each requires a `provider_managed_tool_calls` entry whose tool name matches the requested tool. Text containing `42` or a non-nil completion object is not evidence. Add a structured-outputs example asserting that a JSON-tool fallback success carries `recordable: false` while a native pass (with `response_format_parameter.present?`) does not.

- [ ] **Step 2: Run the checks spec and verify the new examples fail**

Run:

```bash
bundle exec rspec spec/script/smoke/checks_spec.rb
```

Expected: failures for loose substring matching, the vacuous zero-iteration pass, and the weak provider-tool oracles.

- [ ] **Step 3: Implement each hard oracle**

- Completion: `response_text.strip.casecmp("ok").zero?` replaces `text.downcase.include?("ok")` (currently at `script/smoke/checks.rb:117`; apply the same fix to the streaming comparison near `:203` and batch results near `:265`).
- Structured outputs: valid object, exact required keys, non-empty values, and `response_format_parameter.present?` for a recordable native pass. A JSON-tool fallback that produces valid output remains a `:pass` for diagnostics but is tagged `recordable: false`.
- Native tool use: forced tool selection plus parsed hash arguments is sufficient protocol evidence; do not require live Wikipedia execution.
- Streaming: at least one delta received and exact normalized `ok` on both the streamed and unstreamed paths.
- Streaming tool calls: `return { status: :fail, detail: "iterations must be >= 1" } unless iterations >= 1`, then require valid parsed arguments on both paths for every iteration.
- Batch: terminal success, both expected custom IDs present, exact normalized `ok` per result.
- Images/PDFs: the nonce string must appear in the response.
- Provider-managed tools: a `provider_managed_tool_calls` entry with the matching tool name; keep the tool-specific prompts.
- Embeddings: returned vector length equals the declared dimension.

- [ ] **Step 4: Run the checks spec and verify it passes**

Run:

```bash
bundle exec rspec spec/script/smoke/checks_spec.rb
```

Expected: all examples pass.

### Task 3: Validate smoke CLI numeric options

**Files:**
- Modify: `script/smoke.rb`
- Test: `spec/script/smoke/terminal_spec.rb` (or a new focused spec if option parsing is not currently covered there)

**Interfaces:**
- Consumes: the OptionParser block in `script/smoke.rb` (options declared around `:279-301`).
- Produces: `Smoke.validate_options!(options, parser)`, called immediately after parsing and before credential setup or any API call.

- [ ] **Step 1: Write failing validation tests**

If loading `script/smoke.rb` in a spec would execute the runner, extract validation into a method on an already-testable module (`Smoke.validate_options!`) and test that directly:

```ruby
it "rejects zero iterations" do
  expect { Smoke.validate_options!({ iterations: 0, batch_timeout: 60, stale_days: nil }, parser) }
    .to raise_error(SystemExit)
end

it "rejects zero batch timeout" do
  expect { Smoke.validate_options!({ iterations: 1, batch_timeout: 0, stale_days: nil }, parser) }
    .to raise_error(SystemExit)
end

it "rejects negative stale days" do
  expect { Smoke.validate_options!({ iterations: 1, batch_timeout: 60, stale_days: -1 }, parser) }
    .to raise_error(SystemExit)
end
```

- [ ] **Step 2: Run and verify the tests fail**

Run:

```bash
bundle exec rspec spec/script/smoke/terminal_spec.rb
```

Expected: `validate_options!` does not exist yet.

- [ ] **Step 3: Implement validation**

```ruby
def self.validate_options!(options, parser)
  parser.abort("--iterations must be greater than 0") unless options[:iterations].positive?
  parser.abort("--batch-timeout must be greater than 0") unless options[:batch_timeout].positive?
  parser.abort("--stale must be 0 or greater") if options[:stale_days]&.negative?
end
```

Call it in `script/smoke.rb` directly after `parser.parse!`, before credential checks and before any entry selection that could reach an API.

- [ ] **Step 4: Run and verify the tests pass, then exercise the CLI**

```bash
bundle exec rspec spec/script/smoke/terminal_spec.rb
bin/smoke anthropic_claude_5_sonnet --iterations 0
bin/smoke anthropic_claude_5_sonnet --batch-timeout 0
bin/smoke --stale -1
```

Expected: specs pass; each CLI invocation exits nonzero with its specific message before making any API call.

### Task 4: Read-only smoke observation store

**Files:**
- Create: `lib/raif/model_manifest/smoke_observations.rb`
- Test: `spec/lib/raif/model_manifest/smoke_observations_spec.rb`
- Create: `spec/fixtures/model_smoke_results/anthropic.json`
- Create: `model_smoke_results/.gitkeep`

**Interfaces:**
- Consumes: manifest entries (`entry.key`, `entry.provider_name`, `entry.claimed_value(name)`, `entry.smokable_capabilities`). Capability names are normalized with `.to_sym` internally so the store works over string-keyed YAML entries now and symbol-keyed Ruby entries after Task 7.
- Produces (used by Tasks 5 and 6):
  - `Raif::ModelManifest::SmokeObservations::RECORDABLE_POSITIVE_CAPABILITIES` (frozen array of symbols; the single source of truth).
  - `SmokeObservations.load(dir:)` returning a frozen store.
  - `SmokeObservations.recordable_candidates(entry)` returning symbols.
  - `store.fresh?(entry, capability, stale_after_days:, now:)` and `store.stale_capabilities(entry, stale_after_days:, now:)`.

The committed store starts empty: `model_smoke_results/` contains only `.gitkeep`. The existing YAML `verification:` nodes contain no data, so there is no history to migrate. The JSON fixture exists only under `spec/fixtures/`.

- [ ] **Step 1: Define the JSON shape and write the store tests**

Fixture `spec/fixtures/model_smoke_results/anthropic.json`:

```json
{
  "schema_version": 1,
  "models": {
    "anthropic_test_model": {
      "completion": {
        "claimed": true,
        "result": "pass",
        "checked_at": "2026-08-15T14:02:11Z"
      }
    }
  }
}
```

Test these rules in `spec/lib/raif/model_manifest/smoke_observations_spec.rb`:

- a missing observation is stale;
- an observation older than `stale_after_days` is stale;
- an observation whose stored `claimed` differs from the entry's current claim is stale;
- `result != "pass"` never satisfies freshness, even if manually present in the file;
- claimed-false capabilities are never candidates (`recordable_candidates` excludes them);
- `temperature` is never a candidate (non-recordable diagnostics only);
- an empty directory loads successfully and reports everything stale;
- malformed timestamps and unknown `schema_version` values raise a contextual error naming the file, rather than silently looking fresh;
- loaded data is deeply frozen and loading never mutates a manifest entry.

- [ ] **Step 2: Run the store spec and verify it fails**

```bash
bundle exec rspec spec/lib/raif/model_manifest/smoke_observations_spec.rb
```

Expected: the class does not exist.

- [ ] **Step 3: Implement the store**

```ruby
module Raif
  module ModelManifest
    class SmokeObservations
      RECORDABLE_POSITIVE_CAPABILITIES = %i[
        completion structured_outputs native_tool_use streaming
        streaming_tool_calls batch_inference images pdfs
        provider_managed_tools embedding
      ].freeze
      # temperature is intentionally absent: an accepted request does not
      # prove the model honored the parameter.

      def self.load(dir: Raif::Engine.root.join("model_smoke_results"))
        # JSON.parse each *.json; validate schema_version == 1;
        # Time.iso8601 every checked_at; deep-freeze; raise contextual
        # errors that name the offending file and field.
      end

      def self.recordable_candidates(entry)
        # EmbeddingEntry -> [:embedding]
        # LLM entry -> [:completion] + positively claimed recordable capabilities,
        #   plus :streaming_tool_calls only when streaming AND native_tool_use are claimed,
        #   plus :provider_managed_tools only when the declared tool list is non-empty.
      end

      def fresh?(entry, capability, stale_after_days: 30, now: Time.now.utc)
        # symbolized capability; pass-only; claim match; age check
      end

      def stale_capabilities(entry, stale_after_days: 30, now: Time.now.utc)
        self.class.recordable_candidates(entry).reject { |cap| fresh?(entry, cap, stale_after_days:, now:) }
      end
    end
  end
end
```

Implement the commented bodies fully; the comments above define the required behavior, not deferred work. Claimed-false capabilities are excluded at candidate derivation because provider documentation and user approval are authoritative for negative claims.

- [ ] **Step 4: Run the store spec and verify it passes**

```bash
bundle exec rspec spec/lib/raif/model_manifest/smoke_observations_spec.rb
```

Expected: all examples pass.

### Task 5: Record observations post-run; retire the manifest-writing recorder

**Files:**
- Delete: `script/smoke/recorder.rb`
- Delete: `spec/script/smoke/recorder_spec.rb`
- Create: `script/smoke/observation_recorder.rb`
- Test: `spec/script/smoke/observation_recorder_spec.rb`
- Modify: `script/smoke/policy.rb`
- Test: `spec/script/smoke/policy_spec.rb`
- Modify: `script/smoke.rb`
- Modify: `spec/script/smoke/terminal_spec.rb`

**Interfaces:**
- Consumes: `SmokeObservations::RECORDABLE_POSITIVE_CAPABILITIES` and `SmokeObservations.recordable_candidates` from Task 4; per-model results shaped `{ capability_name => { status:, detail:, recordable: (optional) } }` from Tasks 1-2; `entry.source_path`, `entry.provider_name`, `entry.claimed_value`.
- Produces: `Smoke::ObservationRecorder.record_all!(model_results, entries_by_key:, dir:, now:)`; `Smoke::Policy.recordable?(capability, result)`.

- [ ] **Step 1: Write the failing policy tests**

Replace the status-only expectations in `spec/script/smoke/policy_spec.rb`:

```ruby
it "records a hard-oracle pass for a recordable capability" do
  expect(described_class.recordable?("streaming", { status: :pass })).to be(true)
end

it "never records fail, note, skip, or timeout" do
  %i[fail note skip timeout].each do |status|
    expect(described_class.recordable?("streaming", { status: status })).to be(false)
  end
end

it "never records a result tagged recordable: false" do
  expect(described_class.recordable?("structured_outputs", { status: :pass, recordable: false })).to be(false)
end

it "never records a non-recordable capability" do
  expect(described_class.recordable?("temperature", { status: :pass })).to be(false)
end
```

- [ ] **Step 2: Write the failing recorder tests**

In `spec/script/smoke/observation_recorder_spec.rb`, using a temp directory and a fixed `now`, test that `record_all!`:

- writes one provider-named JSON file (`anthropic.json`) per provider that has at least one recordable pass;
- merges untouched prior observations: an existing pass for capability X survives a new run that records capability Y;
- keeps a prior recorded pass when a later run FAILS that same capability (the failure stays terminal output; withdrawing durable evidence is a human decision);
- updates `claimed`, `result`, and `checked_at` for a newly observed pass;
- ignores `:fail`, `:note`, `:skip`, `:timeout`, and `recordable: false` outcomes;
- never opens or writes any file under `model_manifest/`;
- writes nothing at all when the run contains no recordable results;
- records LLM and embedding results for the same provider in one write;
- emits sorted model keys and sorted capability keys, `JSON.pretty_generate(payload) + "\n"`, and is byte-for-byte idempotent on a second run with the same inputs and `now`.

- [ ] **Step 3: Run policy and recorder specs and verify they fail**

```bash
bundle exec rspec spec/script/smoke/policy_spec.rb spec/script/smoke/observation_recorder_spec.rb
```

Expected: policy still records on status alone (current `RECORDABLE_STATUSES = %i[pass fail note]` at `script/smoke/policy.rb:9`); the recorder class does not exist.

- [ ] **Step 4: Implement the policy**

```ruby
def self.recordable?(capability, result)
  Raif::ModelManifest::SmokeObservations::RECORDABLE_POSITIVE_CAPABILITIES.include?(capability.to_sym) &&
    result[:status] == :pass &&
    result.fetch(:recordable, true)
end
```

Remove `RECORDABLE_STATUSES` and the ignored `explicit_keys:` parameter. Do not duplicate the capability list anywhere under `Smoke`; reference the single constant.

- [ ] **Step 5: Implement the recorder**

```ruby
Smoke::ObservationRecorder.record_all!(
  model_results,
  entries_by_key: entries.index_by { |entry| entry.key.to_s },
  dir: Raif::Engine.root.join("model_smoke_results"),
  now: Time.now.utc
)
```

Group recordable passes by `entry.provider_name`. For each provider: read the existing JSON if present, merge new observations over it (never removing entries the run did not positively re-observe), sort keys, and write via a temporary file in the destination directory followed by `File.rename` so an interrupted process cannot leave truncated JSON. Store `claimed` from `entry.claimed_value` at record time.

- [ ] **Step 6: Move recording out of provider threads and delete the old recorder**

Delete `script/smoke/recorder.rb` and `spec/script/smoke/recorder_spec.rb`. Remove `Smoke::Recorder.record!` from `run_entry` (currently `script/smoke.rb:98-102`, executing inside the per-provider threads spawned at `:110-128`). After `run_all` completes:

```ruby
if options[:record]
  Smoke::ObservationRecorder.record_all!(model_results, entries_by_key:, dir: observation_dir)
end
```

Update user-facing text: `--record` help and the pre-run confirmation now say "record successful smoke observations in model_smoke_results/" instead of "write verified results back into the manifest". The final matrix continues to show all statuses whether recorded or not.

- [ ] **Step 7: Run the smoke module specs**

```bash
bundle exec rspec spec/script/smoke
```

Expected: all examples pass; no reference to `Smoke::Recorder` remains (`rg -n 'Smoke::Recorder\b' script spec` returns nothing).

### Task 6: Stale selection via observations; remove embedded verification

**Files:**
- Modify: `script/smoke/selection.rb`
- Test: `spec/script/smoke/selection_spec.rb`
- Modify: `script/smoke.rb`
- Modify: `lib/raif/model_manifest.rb`
- Test: `spec/lib/raif/model_manifest_spec.rb`

**Interfaces:**
- Consumes: `SmokeObservations.load`, `store.stale_capabilities` from Task 4.
- Produces: `Smoke::Selection.resolve(selectors, llm_entries, stale_days:, embedding_entries:, observations:)`; `Entry` and `EmbeddingEntry` without `verification`; `Entry#unverified_capabilities` no longer exists anywhere.

- [ ] **Step 1: Write the failing selection tests**

Rewrite the `--stale` examples in `spec/script/smoke/selection_spec.rb` around an injected store:

```ruby
it "selects an entry when a positively claimed recordable capability has no observation" do
  selected = described_class.resolve([], [entry], stale_days: 30, embedding_entries: [], observations: empty_store)
  expect(selected.keys).to include(entry.key)
end

it "skips an entry whose recordable capabilities are all fresh" do
  selected = described_class.resolve([], [entry], stale_days: 30, embedding_entries: [], observations: fresh_store)
  expect(selected.keys).not_to include(entry.key)
end
```

Add examples that claimed-false capabilities never cause selection and that embedding entries are selected on a stale `:embedding` observation.

- [ ] **Step 2: Update the manifest loader spec**

In `spec/lib/raif/model_manifest_spec.rb`, remove every expectation about `verification` and `unverified_capabilities`, and add an expectation that entries expose no `verification` attribute. Keep YAML loading expectations intact; the format migration is Task 7.

- [ ] **Step 3: Run both specs and verify the failures**

```bash
bundle exec rspec spec/script/smoke/selection_spec.rb spec/lib/raif/model_manifest_spec.rb
```

Expected: `resolve` does not accept `observations:`, and `Entry` still exposes `verification`.

- [ ] **Step 4: Implement**

- In `lib/raif/model_manifest.rb`: remove `verification` from `Entry` (`:76`) and `EmbeddingEntry` (`:126`), delete `Entry#unverified_capabilities` (`:106-120`), and stop reading `model["verification"]` / `endpoint_data["verification"]` during parsing (`:187`, `:200`, `:241`). The now-inert empty `verification:` keys in `model_manifest/*.yml` are ignored by the loader and disappear with the files in Task 8.
- In `script/smoke/selection.rb`: replace the `entry.unverified_capabilities` branch (`:78-82`) with `selected[entry.key] = entry if observations.stale_capabilities(entry, stale_after_days: stale_days).any?`.
- In `script/smoke.rb`: build the store once (`observations = Raif::ModelManifest::SmokeObservations.load`) and pass it to `Selection.resolve`.

- [ ] **Step 5: Run the Phase A gate**

```bash
bundle exec rspec spec/script/smoke spec/lib/raif/model_manifest_spec.rb spec/lib/raif/model_manifest_validity_spec.rb spec/lib/raif/model_manifest/smoke_observations_spec.rb
```

Expected: all green. This is the phase boundary: smoke trust is complete while the manifests are still YAML. `rg -n 'unverified_capabilities|last_full_run_at' lib script spec` returns nothing.

### Task 7: Constrained Ruby manifest DSL

**Files:**
- Create: `lib/raif/model_manifest/dsl.rb`
- Modify: `lib/raif/model_manifest.rb`
- Create: `spec/fixtures/model_manifest/anthropic.rb`
- Create: `spec/fixtures/model_manifest/open_ai.rb`
- Create: `spec/fixtures/model_manifest/embeddings.rb`
- Delete: `spec/fixtures/model_manifest/anthropic.yml`, `spec/fixtures/model_manifest/open_ai.yml`, `spec/fixtures/model_manifest/embeddings.yml`
- Create: `spec/support/legacy_yaml_manifest.rb` (temporary; deleted in Task 8)
- Test: `spec/lib/raif/model_manifest_spec.rb`

**Interfaces:**
- Consumes: the loader shape left by Task 6 (no verification anywhere).
- Produces: `Raif::ModelManifest::Dsl::Context` with `provider(name, &block)` and `embeddings(&block)`; `Raif::ModelManifest::Dsl::UnknownDeclaration`; `Raif::ModelManifest::CAPABILITY_KEYS` and `LIFECYCLE_STATUSES` constants; entries with symbol-keyed frozen `capabilities`, `pricing`, and `lifecycle`; `entry.claimed_value` and `entry.smokable_capabilities` accept string CLI names but read symbol-keyed capabilities.

Note on intent: the constrained context exists to reduce accidental capabilities in manifest files (stray Kernel calls, requires, global mutation). It is not a security sandbox; manifest files are reviewed code.

- [ ] **Step 0: Preserve the legacy YAML loader for the equivalence check**

Before touching the loader, copy the current YAML parsing into `spec/support/legacy_yaml_manifest.rb` as a test-only module (`LegacyYamlManifest.load(dir)`) that reproduces today's `YAML.safe_load_file(path, permitted_classes: [Date], aliases: true)` behavior and entry construction, minus verification. This is migration scaffolding for Task 8 and is deleted there.

- [ ] **Step 1: Write the DSL fixture contract**

Use explicit block arguments so the files read as data construction, not a magical `instance_eval` DSL:

```ruby
# spec/fixtures/model_manifest/anthropic.rb
provider :anthropic do |p|
  p.references models: "https://docs.anthropic.com/models", pricing: "https://claude.com/pricing"

  p.model(
    key: :anthropic_test_model,
    api_name: "test-model-1",
    display_name: "Anthropic Test Model",
    max_completion_tokens: 64_000,
    pricing: { input_per_million: 3.0, output_per_million: 15.0 },
    capabilities: {
      temperature: true,
      structured_outputs: false,
      native_tool_use: true,
      streaming: true,
      batch_inference: true,
      images: false,
      pdfs: false,
      provider_managed_tools: %i[web_search]
    },
    lifecycle: { status: :active, added_on: Date.new(2026, 8, 24) }
  )
end
```

Mirror the current YAML fixtures' content in the new `.rb` fixtures, including an OpenAI fixture with explicit endpoint hashes and an embeddings fixture with adapter class names. Add expectations:

```ruby
expect(entry.provider_name).to eq(:anthropic)
expect(entry.capabilities.fetch(:native_tool_use)).to be(true)
expect(entry.lifecycle.fetch(:added_on)).to eq(Date.new(2026, 8, 24))
expect(entry.capabilities).to be_frozen
expect(entry.lifecycle).to be_frozen
```

Also add a fixture string containing a forbidden top-level call and assert loading raises `Raif::ModelManifest::Dsl::UnknownDeclaration` naming the file path and the declaration.

- [ ] **Step 2: Run the loader spec and verify it fails**

```bash
bundle exec rspec spec/lib/raif/model_manifest_spec.rb
```

Expected: failures for `.rb` fixture loading, symbol-keyed attributes, and the missing DSL classes.

- [ ] **Step 3: Implement the isolated builders**

```ruby
module Raif
  module ModelManifest
    module Dsl
      class Context
        attr_reader :providers, :embedding_providers

        def provider(name, &block)
          builder = ProviderBuilder.new(name:, source_path: current_source_path)
          block.call(builder)
          providers << builder.finish
        end

        def embeddings(&block)
          block.call(EmbeddingRegistryBuilder.new(target: embedding_providers, source_path: current_source_path))
        end
      end
    end
  end
end
```

The builders must:

- accept only the documented DSL methods; evaluate through a `BasicObject`-based context whose `method_missing` raises `UnknownDeclaration`;
- copy and deeply freeze hashes and arrays on `finish`;
- retain `source_path` for validation errors and provider grouping;
- leave semantic validation (known capabilities, replacement targets) to the validity spec;
- support OpenAI endpoint declarations as explicit endpoint hashes and embedding provider blocks with adapter class names.

Load each file with a fresh context and the real filename for backtraces: `context.evaluate(File.read(path), path)`. Do not evaluate through `TOPLEVEL_BINDING` and do not let a manifest file mutate a process-global collector.

- [ ] **Step 4: Rewrite `Raif::ModelManifest.load` around `.rb` declarations**

```ruby
Dir[File.join(dir, "*.rb")].sort.each { |path| context.load_file(path) }
```

```ruby
CAPABILITY_KEYS = %i[
  temperature structured_outputs native_tool_use streaming
  batch_inference images pdfs provider_managed_tools
].freeze

LIFECYCLE_STATUSES = %i[active deprecated retired].freeze
```

Update `smokable_capabilities` and `claimed_value` to accept string CLI names but read symbol-keyed capabilities (Tasks 1-6 already call them with strings; `SmokeObservations` already symbolizes). Preserve the expanded-entry behavior for OpenAI endpoints and the exact runtime keys.

- [ ] **Step 5: Run the loader spec and the smoke suite**

```bash
bundle exec rspec spec/lib/raif/model_manifest_spec.rb spec/script/smoke
```

Expected: loader spec passes. The smoke specs must stay green because they stub entries or use fixtures; if any smoke spec reads YAML fixtures directly, convert those usages now. The authoritative `model_manifest/*.yml` files are temporarily unloadable by the default loader; that is expected between Tasks 7 and 8 and is why both tasks belong to a single suggested commit.

### Task 8: Convert the authoritative manifests with normalized equivalence

**Files:**
- Create: `model_manifest/anthropic.rb`, `model_manifest/bedrock.rb`, `model_manifest/google.rb`, `model_manifest/open_ai.rb`, `model_manifest/open_router.rb`, `model_manifest/x_ai.rb`, `model_manifest/embeddings.rb`
- Delete: `model_manifest/*.yml`
- Delete: `spec/support/legacy_yaml_manifest.rb` (after the equivalence check runs)
- Test: `spec/lib/raif/model_manifest_validity_spec.rb`

**Interfaces:**
- Consumes: the DSL from Task 7; `LegacyYamlManifest.load` from Task 7 Step 0.
- Produces: authoritative Ruby manifests preserving every model's semantics; validity spec enforcing the symbol-keyed schema.

The conversion covers roughly 101 models across 2,768 YAML lines (open_ai 29 models, open_router 27, bedrock 20, anthropic 10, google 6, x_ai 4, embeddings 5). Convert mechanically and let the equivalence check catch mistakes.

- [ ] **Step 1: Update the validity spec for symbol-keyed entries**

```ruby
expect(entry.capabilities.keys.sort).to eq(Raif::ModelManifest::CAPABILITY_KEYS.sort)
entry.capabilities.except(:provider_managed_tools).each_value do |value|
  expect(value).to be(true).or be(false)
end
expect(Raif::ModelManifest::LIFECYCLE_STATUSES).to include(entry.lifecycle.fetch(:status))
```

Add checks that provider references are HTTPS URLs, every non-retired price is a positive `Numeric`, lifecycle dates are `Date` objects, and provider-managed tools are known symbols. Keep the current uniqueness, provider-prefix, replacement-target, and retired-entry rules.

- [ ] **Step 2: Run the validity spec and verify it fails**

```bash
bundle exec rspec spec/lib/raif/model_manifest_validity_spec.rb
```

Expected: failure because `model_manifest/` still contains only YAML, which the new loader does not read.

- [ ] **Step 3: Convert every provider file without changing semantics**

For each YAML provider file preserve: model order, key or OpenAI `key_base`, API and display names, numeric pricing, max completion tokens, all explicit capabilities, lifecycle status and dates, references. Drop the empty `verification:` keys entirely. Convert YAML dates to `Date.new(year, month, day)` and string enums to symbols. A representative deprecated entry:

```ruby
p.model(
  key: :anthropic_old_model,
  api_name: "old-model-1",
  display_name: "Anthropic Old Model",
  pricing: { input_per_million: 3.0, output_per_million: 15.0 },
  capabilities: {
    temperature: true,
    structured_outputs: false,
    native_tool_use: true,
    streaming: true,
    batch_inference: true,
    images: false,
    pdfs: false,
    provider_managed_tools: %i[web_search]
  },
  lifecycle: {
    status: :deprecated,
    added_on: Date.new(2025, 1, 1),
    deprecated_on: Date.new(2026, 8, 1),
    retirement_date: Date.new(2026, 12, 1),
    replacement_key: :anthropic_test_model
  }
)
```

Every model spells out every capability. No shared hashes, no computed defaults.

- [ ] **Step 4: Run the normalized equivalence check**

Add a temporary example that loads the old YAML through `LegacyYamlManifest` and normalizes it to the Ruby representation before comparing. Normalization is explicit because the legacy entries are string-keyed with string enums:

```ruby
def normalize_legacy(entry_hash)
  entry_hash
    .except("verification")
    .deep_symbolize_keys
    .then do |h|
      h.merge(
        lifecycle: h[:lifecycle].merge(status: h.dig(:lifecycle, :status).to_sym),
        capabilities: h[:capabilities].merge(
          provider_managed_tools: Array(h.dig(:capabilities, :provider_managed_tools)).map(&:to_sym)
        )
      )
    end
end

expect(ruby_manifest.llm_entries.map(&:to_h)).to eq(
  legacy_yaml_manifest.llm_entries.map { |e| normalize_legacy(e.to_h) }
)
expect(ruby_manifest.embedding_entries.map(&:to_h)).to eq(
  legacy_yaml_manifest.embedding_entries.map { |e| normalize_legacy(e.to_h) }
)
```

Adjust `normalize_legacy` to cover any other enum-like string fields the comparison surfaces (adapter class names stay strings). Run the example against the still-present YAML files and make it pass.

- [ ] **Step 5: Delete the YAML and the scaffolding, then run the gate**

Delete `model_manifest/*.yml`, the equivalence example, and `spec/support/legacy_yaml_manifest.rb`. Record the equivalence run's passing output in your task notes since it will not exist in the final tree. Then:

```bash
bundle exec rspec spec/lib/raif/model_manifest_spec.rb spec/lib/raif/model_manifest_validity_spec.rb spec/script/smoke
```

Expected: all green, with the same model and embedding key counts as before conversion.

### Task 9: Generator whole-file transforms and exact freshness

**Files:**
- Modify: `lib/raif/model_manifest/registry_data.rb`
- Modify: `lib/raif/model_manifest/generator.rb`
- Test: `spec/lib/raif/model_manifest_generator_spec.rb`
- Test: `spec/lib/raif/generated_artifacts_spec.rb`
- Regenerate: `lib/raif/default_llms.rb`, `lib/raif/default_embedding_models.rb`, `config/locales/en.yml`, `lib/generators/raif/install/templates/initializer.rb`, `docs/_getting_started/setup.md`

**Interfaces:**
- Consumes: symbol-keyed entries from Task 8; the generator's existing pure primitives `replace_yaml_section` (`generator.rb:125-135`) and `replace_between_markers` (`:140-151`), which the write paths already use. Scope note: the primitives and write-path structure already exist and are sound; this task only adds public whole-file composition methods and exact-output tests. Do not restructure the generator.
- Produces: `generator.locale_en(manifest, content)`, `generator.initializer(manifest, content)`, `generator.setup_md(manifest, content)`; a freshness spec using exact equality for all five artifacts.

- [ ] **Step 1: Write failing exact-freshness regression examples**

For each partially generated file, append a stale key inside the generated region and assert the whole-file transform removes it:

```ruby
stale = current.sub(
  "<!-- END GENERATED MODEL KEYS: anthropic -->",
  "- `anthropic_retired_stale`\n<!-- END GENERATED MODEL KEYS: anthropic -->"
)

expect(generator.setup_md(manifest, stale)).not_to eq(stale)
expect(generator.setup_md(manifest, stale)).not_to include("anthropic_retired_stale")
```

Add equivalent cases for `config/locales/en.yml` and the initializer template. In `spec/lib/raif/generated_artifacts_spec.rb`, replace the `include(...)` assertions (`:23-36`) with exact round-trips:

```ruby
content = File.read(path)
expect(content).to eq(generator.locale_en(manifest, content)), hint
```

Keep direct `eq` for the two fully generated Ruby files.

- [ ] **Step 2: Run the specs and verify the new examples fail**

```bash
bundle exec rspec spec/lib/raif/model_manifest_generator_spec.rb spec/lib/raif/generated_artifacts_spec.rb
```

Expected: failures because the whole-file composition methods (`locale_en`, `initializer`, `setup_md`) do not exist yet and the old assertions used substring inclusion.

- [ ] **Step 3: Update registry data to symbol access**

```ruby
input_token_cost: entry.pricing.fetch(:input_per_million).to_f / 1_000_000
tools = entry.capabilities.fetch(:provider_managed_tools)
```

Keep the generated `Raif.default_llms`, `Raif.default_embedding_models`, and `Raif.default_streaming_unsupported_model_keys` public shapes byte-for-byte equivalent apart from the source header comment.

- [ ] **Step 4: Add the whole-file transforms and use them from the write paths**

```ruby
def locale_en(manifest, content)
  content
    .then { |text| replace_yaml_section(text, "model_names", model_names_yaml_block(manifest)) }
    .then { |text| replace_yaml_section(text, "embedding_model_names", embedding_model_names_yaml_block(manifest)) }
end

def initializer(manifest, content)
  content
    .then do |text|
      replace_between_markers(text, INITIALIZER_BEGIN_MARKER, INITIALIZER_END_MARKER, initializer_keys_block(manifest))
    end
    .then do |text|
      replace_between_markers(
        text,
        INITIALIZER_EMBEDDING_BEGIN_MARKER,
        INITIALIZER_EMBEDDING_END_MARKER,
        initializer_embedding_keys_block(manifest)
      )
    end
end

def setup_md(manifest, content)
  SETUP_MD_SECTIONS.reduce(content) do |text, section|
    replace_between_markers(
      text,
      "<!-- BEGIN GENERATED MODEL KEYS: #{section} -->",
      "<!-- END GENERATED MODEL KEYS: #{section} -->",
      setup_md_keys_block(manifest, section)
    )
  end
end
```

`write_locale_en!`, `write_initializer!`, and `write_setup_md!` call these instead of composing the primitives inline. Also fix the stale comments at `generator.rb:124` and `:138-139` claiming the primitives are "used directly by the freshness spec"; after this task the spec uses the whole-file transforms.

- [ ] **Step 5: Regenerate and verify idempotence**

```bash
bin/generate_llm_registry
git diff -- lib/raif/default_llms.rb lib/raif/default_embedding_models.rb config/locales/en.yml lib/generators/raif/install/templates/initializer.rb docs/_getting_started/setup.md
bin/generate_llm_registry
git status --short
```

Expected: the first diff shows only the source header changing from `model_manifest/*.yml` to `model_manifest/*.rb` with no semantic registry changes; the second run changes nothing further (compare `git status` output between runs since nothing is being staged).

- [ ] **Step 6: Run the generator and freshness specs**

```bash
bundle exec rspec spec/lib/raif/model_manifest_generator_spec.rb spec/lib/raif/generated_artifacts_spec.rb
```

Expected: all examples pass.

### Task 10: Update the Claude model-maintenance commands

**Files:**
- Modify: `.claude/commands/model-add.md`
- Modify: `.claude/commands/model-check.md`
- Modify: `.claude/commands/model-retire.md`

**Interfaces:**
- Consumes: the Ruby manifest paths and observation-store semantics from Tasks 4-9.
- Produces: the three commands, retained with their full workflows, pointing at `.rb` manifests and `model_smoke_results/`.

- [ ] **Step 1: Update paths and source-of-truth language in all three commands**

Replace `model_manifest/<provider>.yml` and the `model_manifest/*.yml` glob with `.rb`. State in each command:

```markdown
Provider documentation plus the user's approved proposal determines manifest truth. Smoke output is supporting runtime evidence. Never change a declared capability solely because a generic API request failed.
```

- [ ] **Step 2: Keep `/model-add` smoke mandatory with evidence-aware discrepancy handling**

Retain the full research, citation, approval, branch, generation, smoke, full-suite, diff, and stop-for-review workflow. Change the smoke steps to:

```markdown
4. Smoke it (mandatory): run `bin/smoke` with the newly added model's actual key and `--record`. Missing credentials, SKIP, or TIMEOUT blocks completion.
5. Present the complete matrix. A hard-oracle PASS may be recorded in `model_smoke_results/`. FAIL and NOTE are investigation prompts, not automatic manifest edits. Research any discrepancy against official provider documentation, propose a specific correction with citations, and edit only after user approval.
```

Keep the explicit expensive image-generation follow-up where present.

- [ ] **Step 3: Update `/model-check` stale behavior**

Point the staleness step at `bin/smoke --stale 30` reading `model_smoke_results/*.json` (line 19 currently references "checking verification blocks"). Keep all existing responsibilities: upstream model discovery, pricing drift, lifecycle review, citations, user selection, and per-concern branching.

- [ ] **Step 4: Keep `/model-retire` intact apart from paths and syntax**

Only update file paths and the lifecycle syntax example:

```ruby
lifecycle: {
  status: :deprecated,
  deprecated_on: Date.new(2026, 8, 24),
  retirement_date: Date.new(2026, 12, 1),
  replacement_key: :replacement_model
}
```

Preserve provider-announcement verification, user mode confirmation (DEPRECATE vs REMOVE), regeneration, residue search, tests, lint, changelog, and stop-for-review requirements. Deprecation and removal decisions always rest with the user.

- [ ] **Step 5: Verify no stale references remain**

```bash
rg -n 'model_manifest/.*\.yml|verification blocks|results back into the manifest' .claude/commands
```

Expected: no matches.

### Task 11: Update documentation and the design doc

**Files:**
- Modify: `CONTRIBUTING.md`
- Modify: `CLAUDE.md`
- Modify: `CHANGELOG.md`
- Modify: `docs/_learn_more/customization.md`
- Modify: `docs/_learn_more/streaming.md`
- Modify: `docs/superpowers/specs/2026-08-18-model-lifecycle-design.md`

- [ ] **Step 1: Update manifest format references**

Use `model_manifest/*.rb` consistently. Describe the files as a constrained declarative Ruby DSL that reduces accidental capabilities in manifest files; do not describe it as a sandbox. Document that generated runtime files remain checked in and are never edited directly.

- [ ] **Step 2: Document the observation contract**

In `CONTRIBUTING.md`:

```markdown
`--record` stores only successful observations from checks with concrete pass criteria in `model_smoke_results/`. It never changes declared capabilities and never records FAIL, NOTE, SKIP, or TIMEOUT. A later failure does not remove a previously recorded success; withdrawing or acting on evidence is a maintainer decision. Provider documentation and reviewed manifest changes remain authoritative.
```

Explain that `--stale DAYS` selects models whose positively claimed, recordable capabilities have missing or old successful observations.

- [ ] **Step 3: Correct CHANGELOG claims**

Replace claims that the manifest stores "last verified smoke results" or that the runner verifies both directions. Describe the actual boundary: capability declarations are researched manifest facts; smoke checks exercise claimed support and surface negative-claim diagnostics as NOTE; hard-oracle successes are stored separately in `model_smoke_results/`. No em dashes.

- [ ] **Step 4: Amend the design document**

Update decisions, architecture diagram, schema examples, smoke recording section, migration plan, and testing section in `docs/superpowers/specs/2026-08-18-model-lifecycle-design.md`. The amended data flow:

```text
provider docs/APIs -> Claude research + user approval -> model_manifest/*.rb -> generator
                                                        -> runtime registry/docs
bin/smoke -> terminal diagnostics (all statuses)
          -> successful hard-oracle observations only -> model_smoke_results/*.json
```

Remove all statements that failures confirm unsupported capabilities or that any result record makes a capability verified. Record explicitly: final deprecation and removal decisions, and any withdrawal of stored evidence, are made by a human.

- [ ] **Step 5: Scan for stale terminology**

```bash
rg -n 'model_manifest/.*\.yml|verification block|results back into the manifest|failures are recorded' . --glob '!docs/superpowers/plans/*'
```

Expected: no stale claims in active code, commands, or public documentation. Historical plan documents keep their original wording.

### Task 12: Full regression and quality verification

**Files:**
- Modify as failures require: only files already listed in Tasks 1-11

- [ ] **Step 1: Run all focused specs**

```bash
bundle exec rspec \
  spec/lib/raif/model_manifest_spec.rb \
  spec/lib/raif/model_manifest_validity_spec.rb \
  spec/lib/raif/model_manifest_generator_spec.rb \
  spec/lib/raif/model_manifest/smoke_observations_spec.rb \
  spec/lib/raif/generated_artifacts_spec.rb \
  spec/script/smoke \
  spec/models/raif/llm_spec.rb \
  spec/lib/raif/configuration_spec.rb \
  spec/features/raif/admin/llms_spec.rb
```

Expected: 0 failures.

- [ ] **Step 2: Verify generation idempotence on the working tree**

```bash
bin/generate_llm_registry
git status --short
```

Expected: running the generator changes no files beyond what Task 9 already produced (identical `git status` before and after).

- [ ] **Step 3: Exercise non-network smoke CLI behavior**

```bash
bin/smoke --list
bin/smoke anthropic_claude_5_sonnet --iterations 0
bin/smoke anthropic_claude_5_sonnet --batch-timeout 0
bin/smoke --stale -1
```

Expected: `--list` prints LLM and embedding keys; each invalid numeric invocation exits nonzero before any API call and prints its specific validation message. Do not run `--record` against live APIs.

- [ ] **Step 4: Run the full suite and lint**

```bash
bundle exec rspec
bin/lint
```

Expected: 0 RSpec failures and all linters pass.

- [ ] **Step 5: Review the working tree for forbidden regressions**

```bash
rg -n 'YAML|safe_load|\.yml' lib/raif/model_manifest.rb lib/raif/model_manifest model_manifest .claude/commands CONTRIBUTING.md CLAUDE.md
rg -n 'claim confirmed:|RECORDABLE_STATUSES|Smoke::Recorder\b|unverified_capabilities' script spec lib
```

Expected: no manifest YAML loader remains, no command points at YAML, no exception-confirms-claim path remains, no status-only recordability remains, and no embedded-verification API survives. (`config/locales/en.yml` references outside the manifest loader are expected and fine.)

- [ ] **Step 6: Leave everything uncommitted**

Do not commit. Report the final `git status --short` and the spec/lint results, then hand off to the maintainer for the commit-workflow pass using the suggested commit plan below.

---

## Suggested commit plan (for commit-workflow, applied after implementation)

Each suggested commit is independently green under the focused smoke and manifest specs:

1. `fix: make smoke verdicts claim-aware and evidence-based` (Tasks 1-2: `script/smoke/checks.rb`, `spec/script/smoke/checks_spec.rb`)
2. `fix: validate smoke CLI numeric options` (Task 3: `script/smoke.rb`, terminal spec)
3. `feat: add a separate smoke observation store` (Task 4: `lib/raif/model_manifest/smoke_observations.rb`, spec, fixtures, `model_smoke_results/.gitkeep`)
4. `refactor: record smoke observations after the run` (Task 5: policy, observation recorder, recorder deletion, `script/smoke.rb`)
5. `refactor: drive stale selection from observations` (Task 6: selection, loader verification removal, specs)
6. `refactor: migrate model manifest data to Ruby` (Tasks 7-9 together: DSL, loader, fixtures, authoritative manifests, validity spec, generator symbol keys, exact freshness, regenerated artifacts. Execution showed the generator specs stay red between Tasks 8 and 9, so 7+8 alone is not a green boundary; land all three as one commit)
7. `docs: align model commands and docs with the new design` (Tasks 10-11)

Post-review fix wave (from the final whole-branch review): the claimed-value round-trip normalization (`smoke_observations.rb`, `observation_recorder.rb` and specs) belongs with commit 3 or 4; the selection_spec JSON-backed store helpers with commit 5; the CHANGELOG/design-doc grammar fixes with commit 7. Since everything is uncommitted, fold each file's changes into the commit that owns that file.

No Co-Authored-By trailers. No em dashes in commit messages.

---

## Acceptance criteria

- A claimed-false capability that works is displayed as `NOTE`, never `PASS`, including expensive explicitly requested checks; cheap probe successes keep their existing `NOTE` behavior.
- A generic exception never confirms an unsupported claim; claimed-false probe exceptions are `FAIL`.
- Completion, streaming, and batch oracles require exact normalized `ok`; provider-managed tool checks require matching `provider_managed_tool_calls` evidence; zero iterations cannot pass.
- Zero or negative iterations/timeouts/stale-days are rejected before any API call.
- `--record` writes only hard-oracle passes for recordable capabilities to `model_smoke_results/*.json`, after all threads finish, never touching `model_manifest/`; fail, note, skip, and timeout are never persisted; a later failure never removes a stored success.
- `model_smoke_results/` starts empty except `.gitkeep`; observation JSON is sorted, schema-versioned, and idempotent to rewrite.
- `--stale` selects on missing or old successful observations for positively claimed recordable capabilities only.
- `model_manifest/` contains only authoritative Ruby declarations with every capability spelled out per model; no verification state remains anywhere in manifests, entries, or loader.
- Normalized YAML-vs-Ruby equivalence was demonstrated before the YAML files were deleted.
- Runtime registry keys, prices, adapter settings, display names, streaming fallback behavior, and deprecation behavior are unchanged by the migration.
- Generated artifacts fail CI on both missing and extra entries inside generated regions (exact whole-file comparison).
- The three Claude model commands remain present with research, citation, approval, mandatory smoke, and stop-for-review workflows; deprecation and removal decisions rest with the user.
- Focused specs, full RSpec, lint, and generator idempotence all pass; nothing is committed.
