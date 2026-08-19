# Model Lifecycle Management System

**Date:** 2026-08-18 (amended 2026-08-19 after external review)
**Status:** Approved design, pending implementation plan

## Problem

New models are released frequently, pricing changes, and existing models get deprecated. Today, keeping raif current is entirely manual:

- Adding or removing a model touches 5-6 files (`lib/raif/llm_registry.rb`, `config/locales/en.yml`, the initializer template, `docs/_getting_started/setup.md`, `CHANGELOG.md`, sometimes specs and VCR cassettes). Only the locale mismatch is caught by CI.
- Smoke testing is split across four ad hoc scripts (`bin/smoke_llm_models`, `bin/probe_structured_outputs`, `bin/probe_streaming_tool_calls`, `bin/probe_bedrock_stream_transport`) plus `bin/smoke_embedding_models`. Each duplicates selector and credential logic, results go only to stdout, and nothing verifies that a model's claimed capabilities match reality. This is how a Grok model shipped with `supports_batch_inference` claimed but no batch API behind it.
- There is no deprecation mechanism. Retirement is a manual multi-file delete plus a breaking-change CHANGELOG entry, and upcoming retirement dates are tracked in maintainers' heads.
- Capability facts are scattered: some in `model_provider_settings`, some as adapter class methods, streaming support as a config blocklist, and image/PDF support not modeled at all.

## Goals

1. Check for new models, pricing changes, and deprecations on demand.
2. Smoke existing models and flag ones that are not working or not verified.
3. Add a new model, smoke it, and surface discrepancies before release.
4. Draft branches and PRs for each concern.
5. Interactive throughout: Claude researches, reports findings, and asks before acting. Accepts hints (a model name, a pasted URL) as the primary entry point.

## Decisions

- **Persistent machine-readable state:** a model manifest with lifecycle dates, expected capabilities, and recorded smoke results.
- **Manifest generates the registry:** the manifest is the single source of truth; `lib/raif/llm_registry.rb` and related artifacts are generated from it with CI enforcement.
- **Deprecation is a runtime feature:** deprecated models log a warning with migration guidance; the admin UI badges them.
- **On-demand only for v1:** no scheduled CI job or repo secrets yet, but scripts produce machine-readable output and nonzero exit codes so a scheduled workflow can be added later.
- **Big bang delivery:** manifest, generator, smoke runner, runtime deprecation, and Claude skills land together in one release.
- **Smoke scripts are consolidated, not kept:** one runner with capability-scoped flags replaces the five existing scripts, with a clean cut (no compatibility stubs).

## Architecture

Five components. Data flows one way:

```
provider docs/APIs -> (Claude research) -> model_manifest/ -> generator
    -> registry / locale / initializer template / setup docs
bin/smoke verifies reality against manifest claims -> results recorded back into manifest
```

1. **Model manifest**: YAML files under `model_manifest/`, one per provider plus `embeddings.yml`. Single source of truth for identity, pricing, capabilities, lifecycle, and verification state.
2. **Registry generator**: `bin/generate_llm_registry` emits the checked-in artifacts currently maintained by hand.
3. **Capability-matrix smoke runner**: `bin/smoke` tests each model against exactly what the manifest claims and records results.
4. **Claude workflow skills**: `/model-check`, `/model-add`, `/model-retire` in `.claude/commands/`.
5. **Runtime deprecation support**: warnings and admin badges driven by manifest lifecycle fields.

## Component 1: Model manifest

One YAML file per provider under `model_manifest/` (e.g. `anthropic.yml`, `bedrock.yml`, `open_ai.yml`, `open_router.yml`, `x_ai.yml`, `google.yml`), plus `embeddings.yml` for the embedding model registry.

### Schema

```yaml
provider: anthropic
references:
  models_doc: https://docs.claude.com/en/docs/about-claude/models
  pricing: https://claude.com/pricing
  deprecations: https://docs.claude.com/en/docs/about-claude/model-deprecations
models:
  - key: anthropic_claude_5_sonnet
    api_name: claude-sonnet-5
    display_name: Claude Sonnet 5
    max_completion_tokens: 64000
    pricing:
      input_per_million: 3.00
      output_per_million: 15.00
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
      status: active            # active | deprecated | retired
      added_on: 2025-11-24
      deprecated_on: null
      retirement_date: null
      replacement_key: null
      migration_note: null
    verification:
      last_full_run_at: 2026-08-15T14:02:11Z   # written only by a complete, unskipped run
      results:
        completion:         { claimed: true, result: pass, checked_at: 2026-08-15T14:02:11Z }
        structured_outputs: { claimed: true, result: pass_native, checked_at: 2026-08-15T14:02:11Z }  # or pass_json_tool
        streaming:          { claimed: true, result: pass, checked_at: 2026-08-15T14:02:11Z }
        streaming_tool_calls: { claimed: true, result: pass, checked_at: 2026-08-15T14:02:11Z }
        batch_inference:    { claimed: true, result: pass, checked_at: 2026-08-15T14:02:11Z }
        images:             { claimed: true, result: pass, checked_at: 2026-08-15T14:02:11Z }
```

### OpenAI endpoint variants

OpenAI models are served through two runtime endpoints (Completions and Responses) whose capabilities, provider-managed tools, and smoke outcomes differ, and six models exist only on Responses. The key rewrite is therefore not left implicit in generator code. OpenAI manifest entries declare explicit endpoints:

```yaml
- key_base: gpt_5_2          # generates open_ai_gpt_5_2 and open_ai_responses_gpt_5_2
  api_name: gpt-5.2
  display_name: GPT-5.2
  pricing: { ... }           # shared: identical across endpoints
  lifecycle: { ... }         # shared: OpenAI deprecates models, not endpoints
  endpoints:
    completions:
      capabilities: { ... }
      verification: { ... }
    responses:
      capabilities: { ..., provider_managed_tools: [web_search, code_execution, image_generation] }
      verification: { ... }
```

Responses-only models declare only the `responses` endpoint. Capabilities and verification are per generated key; pricing and lifecycle are shared at the model level.

### Schema decisions

- **Pricing is per-million tokens**, as providers publish it. The generator converts to per-token. This normalizes the Bedrock entries that currently use a per-thousand divisor.
- **Capabilities are complete, not exception-based.** Every capability is explicit per model so the smoke runner can verify each claimed `true`. The generator maps these back to the runtime representation (`model_provider_settings`, the `streaming_unsupported_model_keys` default, etc.); the runtime shape does not change.
- **Retired models stay in the file** with `status: retired` and their dates. The generator skips them. This preserves a permanent record of what existed and when it left, and lets `/model-check` warn about approaching retirement dates mechanically.
- **`verification` is machine-written only.** Only `bin/smoke --record` updates it. Results are per capability, each recording the claimed value, the observed result, and `checked_at`; a partial run (`--only`, `--skip`) updates only the capabilities it actually exercised. `last_full_run_at` is written only by a complete, unskipped run. A capability is unverified when its record is missing, stale, or its recorded `claimed` value no longer matches the current claim (so editing a capability automatically invalidates its old verification).
- **`migration_note`** is a freeform string for deprecations with no clean upgrade: no successor exists, the successor is not drop-in (pricing tier, capability loss), or the best alternative is another provider. `replacement_key` may name a model from any provider since keys are global.
- **Provider-class cache-cost multipliers stay in generator/adapter code**, not the manifest; they are structural per-provider rules. The OpenAI Responses split, by contrast, is modeled explicitly via `endpoints` (see above), not as a generator-side key rewrite.
- **`display_name` is a required manifest field.** The existing `en.yml` names are curated (ordering, suffixes like "(via AWS Bedrock)" and "(Responses API)"), so derivation from keys is not attempted. The extraction script bootstraps every current locale value verbatim; the generator emits locale entries from this field.

## Component 2: Registry generator

`bin/generate_llm_registry` (wrapping `script/generate_llm_registry.rb`, following the existing `bin/* -> script/*.rb` pattern). Idempotent. Emits four checked-in artifacts; raif's boot process is unchanged and the gem gains no runtime YAML parsing.

1. `lib/raif/llm_registry.rb`: fully generated, with a "GENERATED FROM model_manifest/ - do not edit" header. Same public shape (`Raif.default_llms` returns the same hash) so `engine.rb` and everything downstream is untouched. Generated Ruby keeps registry diffs reviewable in PRs.
2. `config/locales/en.yml`: the `raif.model_names:` and `embedding_model_names:` sections, rewritten between marker comments. Hand-written content elsewhere is untouched.
3. `lib/generators/raif/install/templates/initializer.rb`: the available-key comment lists, between markers.
4. `docs/_getting_started/setup.md`: the per-provider key lists, between markers.

### CI enforcement

Two specs, both offline:

- **Manifest validity**: required fields present; keys unique and prefixed with their provider; `replacement_key`, when present, must point to an *active* model on `status: deprecated` entries (the runtime warning is actively recommending it) but need only *exist* in the manifest, any status, on `status: retired` entries (historical record; replacements legitimately retire later). `/model-check` flags deprecated models whose replacement has itself become deprecated. Pricing present for non-retired models; `retirement_date` required when `status: deprecated`; capability keys drawn from a known set so typos fail instead of silently reading as unsupported.
- **Freshness**: runs the generator in memory and asserts the four checked-in artifacts match byte-for-byte, with a failure message naming `bin/generate_llm_registry`. Subsumes the existing locale-key spec and extends the guarantee to the initializer template and setup docs.

**Deliberate exclusion:** CI does not fail when a `retirement_date` passes. Time-based CI failures break unrelated PRs. Overdue retirements are surfaced by `/model-check` and the smoke runner summary instead.

## Component 3: Capability-matrix smoke runner

`bin/smoke` (wrapping `script/smoke.rb`) replaces `bin/smoke_llm_models`, `bin/smoke_embedding_models`, `bin/probe_structured_outputs`, `bin/probe_streaming_tool_calls`, and `bin/probe_bedrock_stream_transport`. Clean cut: old scripts are deleted, `CONTRIBUTING.md` smoke section rewritten. Selector parsing and credential gating are written once (credential map carried over from the current scripts). Providers without credentials are skipped with a clear note.

### Selection and scoping

```bash
bin/smoke anthropic_claude_5_sonnet                    # one model, full matrix
bin/smoke anthropic                                    # provider prefix
bin/smoke --all
bin/smoke --stale [days]                               # any capability unverified, claim-changed, or checked > N days ago
bin/smoke x_ai --only batch_inference                  # capability-scoped
bin/smoke bedrock_claude_5_sonnet --only streaming --iterations 5
```

Capability-specific options hang off `--only` (e.g. `--iterations` for streaming, `--timeout` for batch). `--skip batch` exists because batch polling dominates wall-clock time.

### Skip semantics and the add-model gate

Skips must not be able to masquerade as verification:

- **Explicitly selected models** (named by key on the command line): any `SKIP`, `TIMEOUT`, or required check left unexecuted (missing credentials included) exits nonzero, and `--record` refuses to stamp the affected capabilities. This is what makes `/model-add`'s smoke step a real gate; a new model cannot pass it without credentials for its provider.
- **Pattern and sweep selections** (provider prefix, `--all`, `--stale`): providers without credentials are skipped with a clear note and do not fail the run. `--strict` upgrades sweeps to the explicit-selection policy for a future scheduled CI job.

### Test matrix (derived from the manifest entry)

| Capability | Test |
|---|---|
| completion | "reply with exactly: ok" check |
| temperature | request with explicit temperature; assert no API error |
| structured_outputs | JSON-schema task; verify valid conforming JSON and record which path was used (native vs `json_response` tool fallback) |
| native_tool_use | tool-call prompt; also covers forced tool choice |
| streaming | plain-text prompt streamed vs unstreamed, deterministic expected output; isolates streaming from tool calling |
| streaming_tool_calls | tool-call prompt streamed vs unstreamed, diffed; run only when `native_tool_use` is claimed (absorbs the streaming-tool-calls and Bedrock transport probes) |
| batch_inference | minimal 2-item batch, poll with timeout; timeout reports as TIMEOUT, distinct from FAIL |
| images / pdfs | fixture image and PDF containing rendered nonce text (e.g. `RAIF-SMOKE-7391`); assert the nonce appears in the response |
| provider_managed_tools | one cheap invocation per declared tool |
| embeddings | embed a short string; assert vector of declared size |

### Both directions

- Claimed `true` that fails: FAIL, nonzero exit.
- Claimed `false` on cheap capabilities (temperature, structured outputs): probed anyway; working ones report `NOTE: claimed unsupported but appears to work`.

### Output and recording

Per-model pass/fail matrix on stdout; `--format json` for machine consumption (makes a future scheduled CI job trivial); `--record` writes per-capability results (claimed value, observed result, `checked_at`) into the manifest `verification` block, and `last_full_run_at` only when the run was complete and unskipped. Failures are recorded too, not just passes. Models within a provider run sequentially; providers run in parallel threads.

## Component 4: Claude workflow skills

Three commands in `.claude/commands/`, alongside `release-prep.md`. Shared contract: research, report, confirm, act. No file edits before an approved concrete proposal. One PR per concern. All PRs are drafts.

### /model-check [hint]

The patrol. Bare invocation asks "anything specific that prompted this, or general sweep?" Arguments scope it: a provider, a concern (`pricing openai`), a pasted URL, or a rumor ("heard Gemini 3 dropped").

1. Gather from manifest reference URLs, provider list-models APIs where available, and web search. A user-supplied URL is used directly and added to that provider's `references` for next time.
2. Cross-reference against the manifest: models upstream but not here; pricing differences; announced deprecations not recorded; retirement dates near or past; models with stale or missing verification; deprecated models approaching retirement with neither `replacement_key` nor `migration_note`.
3. Present one findings report grouped by action type, each item with cited sources; ask which to act on.
4. For approved items: handle in-session, or when several independent concerns exist, write one handoff doc per concern in `docs/handoffs/` (existing Goal / Current State / Next Steps template) for parallel sessions. User chooses at that prompt.

Pricing updates have no dedicated command; the check flow handles them inline (edit manifest, regenerate, changelog, PR).

### /model-add <name or URL>

1. Research from the hint; propose a complete manifest entry with sources cited and guesses flagged as guesses (e.g. "no batch API documented, claiming `batch_inference: false`").
2. On approval: branch, edit manifest, run `bin/generate_llm_registry`, run `bin/smoke <key> --record`.
3. Present the smoke matrix. Discrepancies loop: adjust claim, regenerate, re-smoke. Mandatory, not skippable.
4. Draft CHANGELOG entry and PR description (including the smoke matrix as evidence), commit, open a draft PR.

### /model-retire <key>

Two modes:

- **Deprecate**: set `status: deprecated`, `deprecated_on`, `retirement_date`, and `replacement_key` or `migration_note` from the provider announcement. When no successor is named, ask: propose the closest alternative with caveats, or record no replacement. Regenerate (activating the runtime warning); CHANGELOG note; draft PR.
- **Remove** (at or after retirement date): flip to `status: retired`, regenerate, migrate specs/cassettes using the key to the replacement, write the breaking-change CHANGELOG entry citing the provider page; draft PR.

### Encoded conventions

The command files encode repo conventions so they are followed mechanically: CHANGELOG format and prefixes (`**Breaking change**:`, `**Behavior Change**:`), no AI attribution in commits, no em or en dashes, content stays generic to raif.

## Component 5: Runtime deprecation behavior

`Raif::Llm` gains three optional attributes: `deprecated` (boolean), `retirement_date`, `replacement_key` (plus the migration note text for messaging).

- **Warning on use, once per process per key.** Instantiating a deprecated model via `Raif.llm(key)` logs one `Rails.logger.warn`. Message forms, by available data:
  - With `replacement_key`: "Raif model :x is deprecated and will be removed after DATE. Use :y instead."
  - With only `migration_note`: the note verbatim, appended to the deprecation line.
  - With neither: "Raif model :x is deprecated and will be removed after DATE."
- **Boot-time check.** The existing configuration validation (which raises when `default_llm_model_key` is unknown) additionally warns when the configured default is deprecated.
- **Admin UI.** The admin LLMs index badges deprecated models with their retirement date.
- No behavioral gating; deprecated models work normally until removed. No config knob to silence warnings unless someone asks for one.

## Testing and migration

### Migration safety

1. A one-time extraction script bootstraps the manifest from the current hand-written registry (including copying every current `en.yml` display name verbatim into `display_name` fields), then is deleted.
2. A temporary equivalence spec asserts the generated `Raif.default_llms` hash equals the current hand-written one (every key, cost, and setting), and that the generated locale sections reproduce the current `raif.model_names` / `embedding_model_names` entries exactly, before the hand-written data is removed. This guards against an unintended user-facing rename migration.
3. Capability facts not modeled today (per-model images/PDFs) start as researched claims; a full `bin/smoke --all --record` pass truth-tests them and seeds every `verification` block.

### Ongoing coverage

- Manifest validity and freshness specs run in normal CI; no live APIs.
- Generator: unit specs against a small fixture manifest.
- Smoke runner logic (selector parsing, credential gating, matrix derivation): unit specs with `TestLlm`. Live-API paths remain manually invoked.
- Deprecation warning and admin badge: standard specs.
- The existing provider specs and VCR cassettes are untouched; request/response behavior does not change.

### Delivery

One branch, ordered so each commit leaves the suite green:

1. Manifest files + extraction script + equivalence spec (the hand-written registry data is snapshotted to a spec fixture so the equivalence spec has a stable comparison target).
2. Generator + freshness/validity specs + generated artifacts (generation replaces the hand-written content of `llm_registry.rb`; equivalence spec compares against the fixture).
3. Delete equivalence scaffolding, the fixture snapshot, and the extraction script.
4. Smoke runner + delete old scripts + CONTRIBUTING update.
5. Deprecation runtime + admin badge.
6. The three command files.

## Out of scope for v1

- Scheduled CI smoke runs and provider API keys as repo secrets (design keeps the door open: JSON output, nonzero exits).
- Automatic pricing feeds; pricing changes flow through `/model-check` research.
- Behavioral gating of deprecated models.
- Modeling context-window size (only `max_completion_tokens` exists today; unchanged).
