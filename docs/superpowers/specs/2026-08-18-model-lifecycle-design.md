# Model Lifecycle Management System

**Date:** 2026-08-18 (amended 2026-08-19 after external review; amended 2026-08-24 to match the implemented design)
**Status:** Implemented. The sections below describe the system as built, which diverged from the original design in two ways: the manifest is a constrained Ruby DSL (`model_manifest/*.rb`), not YAML, and live smoke evidence is stored separately from the manifest (`model_smoke_results/*.json`) rather than written back into it.

## Problem

New models are released frequently, pricing changes, and existing models get deprecated. Today, keeping raif current is entirely manual:

- Adding or removing a model touches 5-6 files (`lib/raif/default_llms.rb`, `config/locales/en.yml`, the initializer template, `docs/_getting_started/setup.md`, `CHANGELOG.md`, sometimes specs and VCR cassettes). Only the locale mismatch is caught by CI.
- Smoke testing is split across four ad hoc scripts (`bin/smoke_llm_models`, `bin/probe_structured_outputs`, `bin/probe_streaming_tool_calls`, `bin/probe_bedrock_stream_transport`) plus `bin/smoke_embedding_models`. Each duplicates selector and credential logic, results go only to stdout, and nothing verifies that a model's claimed capabilities match reality. This is how a Grok model shipped with `supports_batch_inference` claimed but no batch API behind it.
- There is no deprecation mechanism. Retirement is a manual multi-file delete plus a breaking-change CHANGELOG entry, and upcoming retirement dates are tracked in maintainers' heads.
- Capability facts are scattered: some in `model_provider_settings`, some as adapter class methods, streaming support as a config blocklist, and image/PDF support not modeled at all.

## Goals

1. Check for new models, pricing changes, and deprecations on demand.
2. Smoke existing models and flag ones that are failing or lack fresh recorded evidence.
3. Add a new model, smoke it, and surface discrepancies before release.
4. Draft branches and PRs for each concern.
5. Interactive throughout: Claude researches, reports findings, and asks before acting. Accepts hints (a model name, a pasted URL) as the primary entry point.

## Decisions

- **Persistent machine-readable state, split in two:** a model manifest with lifecycle dates and expected capabilities, and a separate store of recorded smoke observations. The manifest holds claims a human researched and approved; the observation store holds evidence a machine produced by exercising those claims against a live API. The two are never merged into one record.
- **Manifest is a constrained Ruby DSL, not a sandbox:** `model_manifest/*.rb` files are plain Ruby, evaluated against a restricted context that understands only `provider` and `embeddings` declarations. This reduces accidental capabilities in manifest files (stray requires, global mutation, arbitrary method calls) so a manifest diff stays about model facts. It is not a security boundary and is never described as one; manifest files remain reviewed, committed code like any other source file.
- **Manifest generates the registry:** the manifest is the single source of truth for identity, pricing, capabilities, and lifecycle; `lib/raif/default_llms.rb` and related artifacts are generated from it with CI enforcement.
- **Deprecation is a runtime feature:** deprecated models log a warning with migration guidance; the admin UI badges them.
- **On-demand only for v1:** no scheduled CI job or repo secrets yet, but scripts produce machine-readable output and nonzero exit codes so a scheduled workflow can be added later.
- **Big bang delivery:** manifest, generator, smoke runner, runtime deprecation, and Claude skills land together in one release.
- **Smoke scripts are consolidated, not kept:** one runner with capability-scoped flags replaces the five existing scripts, with a clean cut (no compatibility stubs).
- **Smoke evidence never touches the manifest:** `bin/smoke --record` writes only to `model_smoke_results/*.json`, and only for a hard-oracle pass on a capability with a concrete, checkable pass criterion. It never edits `model_manifest/*.rb` and never records FAIL, NOTE, SKIP, or TIMEOUT. A later failing run never removes a previously recorded success, and a claimed-false capability that turns out to work is reported as NOTE, not treated as verifying anything. Withdrawing or acting on stored evidence, like any deprecation or removal decision, is made by a human maintainer, not by an automated run.

## Architecture

Five components. Two independent data flows, not one:

```text
provider docs/APIs -> Claude research + user approval -> model_manifest/*.rb -> generator
                                                        -> runtime registry/docs
bin/smoke -> terminal diagnostics (all statuses)
          -> successful hard-oracle observations only -> model_smoke_results/*.json
```

The manifest flow is the only path that changes what Raif ships: a human-approved capability claim moves through the generator into the runtime registry and docs. The smoke flow is diagnostic and evidentiary only: it reads the manifest's claims to know what to check, prints terminal diagnostics for every status it observes (pass, fail, note, skip, timeout), and separately persists only the subset of passes a hard oracle actually confirmed. Nothing on the smoke side writes back into `model_manifest/*.rb`, and no stored observation or terminal result upgrades a manifest capability to "verified"; the manifest capability remains a claim, and the observation store remains an independently readable record of evidence about it.

1. **Model manifest**: a constrained Ruby DSL under `model_manifest/`, one file per provider plus `embeddings.rb`. Single source of truth for identity, pricing, capabilities, and lifecycle.
2. **Registry generator**: `bin/generate_llm_registry` emits the checked-in artifacts currently maintained by hand.
3. **Capability-matrix smoke runner**: `bin/smoke` tests each model against exactly what the manifest claims, reports every status to the terminal, and records only hard-oracle passes to `model_smoke_results/*.json`.
4. **Claude workflow skills**: `/model-check`, `/model-add`, `/model-retire` in `.claude/commands/`.
5. **Runtime deprecation support**: warnings and admin badges driven by manifest lifecycle fields.

## Component 1: Model manifest

One Ruby file per provider under `model_manifest/` (e.g. `anthropic.rb`, `bedrock.rb`, `open_ai.rb`, `open_router.rb`, `x_ai.rb`, `google.rb`), plus `embeddings.rb` for the embedding model registry. Each file is plain Ruby, but evaluated against a restricted DSL context that answers only `provider`, `embeddings`, and `Date`; anything else raises instead of reaching Kernel. This keeps a manifest file from acquiring capabilities nobody meant to give it (requires, IO, global mutation) by accident. It is a constraint on accidental scope, not a security sandbox: manifest files are reviewed, committed code, and a determined author could still break out.

There is no verification or smoke-result field anywhere in the manifest. A model's capabilities are a researched, human-approved claim; live evidence about whether that claim holds lives entirely in the separate smoke-observations store described in Component 3.

### Schema

```ruby
provider :anthropic do |p|
  p.references(
    models_doc: "https://docs.claude.com/en/docs/about-claude/models",
    pricing: "https://claude.com/pricing",
    deprecations: "https://docs.claude.com/en/docs/about-claude/model-deprecations"
  )

  p.model(
    key: :anthropic_claude_5_sonnet,
    api_name: "claude-sonnet-5",
    display_name: "Claude Sonnet 5",
    max_completion_tokens: 64_000,
    pricing: { input_per_million: 3.00, output_per_million: 15.00 },
    capabilities: {
      temperature: false,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: true,
      images: true,
      pdfs: true,
      provider_managed_tools: %i[web_search code_execution]
    },
    lifecycle: {
      status: :active            # :active | :deprecated | :retired
    }
  )
end
```

A deprecated model fills in the rest of `lifecycle`; every field beyond `status` defaults to `nil` when omitted:

```ruby
lifecycle: {
  status: :deprecated,
  added_on: Date.new(2025, 11, 24),
  deprecated_on: Date.new(2026, 6, 1),
  retirement_date: Date.new(2026, 12, 1),
  replacement_key: :anthropic_claude_5_sonnet,
  migration_note: nil
}
```

### OpenAI endpoint variants

OpenAI models are served through two runtime endpoints (Completions and Responses) whose capabilities, provider-managed tools, and smoke outcomes differ, and six models exist only on Responses. The key rewrite is therefore not left implicit in generator code. OpenAI manifest entries declare explicit endpoints:

```ruby
p.model(
  key_base: :gpt_5_2,          # generates open_ai_gpt_5_2 and open_ai_responses_gpt_5_2
  api_name: "gpt-5.2",
  display_name: "GPT-5.2",
  pricing: { ... },            # shared: identical across endpoints
  lifecycle: { ... },          # shared: OpenAI deprecates models, not endpoints
  endpoints: {
    completions: {
      capabilities: { ... }
    },
    responses: {
      capabilities: { ..., provider_managed_tools: %i[web_search code_execution image_generation] }
    }
  }
)
```

Responses-only models declare only the `responses` endpoint. Capabilities are per generated key; pricing and lifecycle are shared at the model level. Smoke observations are also per generated key, in the observation store, since `open_ai_gpt_5_2` and `open_ai_responses_gpt_5_2` are checked independently.

### Schema decisions

- **Pricing is per-million tokens**, as providers publish it. The generator converts to per-token. This normalizes the Bedrock entries that currently use a per-thousand divisor.
- **Capabilities are complete, not exception-based.** Every capability is explicit per model so the smoke runner can verify each claimed `true`. The generator maps these back to the runtime representation (`model_provider_settings`, the `streaming_unsupported_model_keys` default, etc.); the runtime shape does not change.
- **Retired models stay in the file** with `status: retired` and their dates. The generator skips them. This preserves a permanent record of what existed and when it left, and lets `/model-check` warn about approaching retirement dates mechanically.
- **The manifest has no verification field.** Live smoke evidence is not part of the manifest at all; it lives in the separate `model_smoke_results/*.json` store described under Component 3. This keeps a manifest diff purely about researched capability claims, and means `bin/smoke --record` never touches `model_manifest/*.rb`.
- **`migration_note`** is a freeform string for deprecations with no clean upgrade: no successor exists, the successor is not drop-in (pricing tier, capability loss), or the best alternative is another provider. `replacement_key` may name a model from any provider since keys are global.
- **Provider-class cache-cost multipliers stay in generator/adapter code**, not the manifest; they are structural per-provider rules. The OpenAI Responses split, by contrast, is modeled explicitly via `endpoints` (see above), not as a generator-side key rewrite.
- **`display_name` is a required manifest field.** The existing `en.yml` names are curated (ordering, suffixes like "(via AWS Bedrock)" and "(Responses API)"), so derivation from keys is not attempted. The extraction script bootstraps every current locale value verbatim; the generator emits locale entries from this field.

## Component 2: Registry generator

`bin/generate_llm_registry` (wrapping `script/generate_llm_registry.rb`, following the existing `bin/* -> script/*.rb` pattern). Idempotent. Emits five checked-in artifacts; raif's boot process is unchanged and the gem gains no runtime YAML or Ruby-manifest parsing at boot.

1. `lib/raif/default_llms.rb`: fully generated, with a "GENERATED FROM model_manifest/ - do not edit" header. Same public shape (`Raif.default_llms` returns the same hash) so `engine.rb` and everything downstream is untouched. Generated Ruby keeps registry diffs reviewable in PRs.
2. `lib/raif/default_embedding_models.rb`: fully generated, same pattern, for the embedding model registry.
3. `config/locales/en.yml`: the `raif.model_names:` and `embedding_model_names:` sections, rewritten between marker comments. Hand-written content elsewhere is untouched.
4. `lib/generators/raif/install/templates/initializer.rb`: the available-key comment lists, between markers.
5. `docs/_getting_started/setup.md`: the per-provider key lists, between markers.

All five generated files stay checked in and are never hand-edited; `bin/generate_llm_registry` is the only path that writes them.

### CI enforcement

Two specs, both offline:

- **Manifest validity**: required fields present; keys unique and prefixed with their provider; `replacement_key`, when present, must point to an *active* model on `status: deprecated` entries (the runtime warning is actively recommending it) but need only *exist* in the manifest, any status, on `status: retired` entries (historical record; replacements legitimately retire later). `/model-check` flags deprecated models whose replacement has itself become deprecated. Pricing present for non-retired models; `retirement_date` required when `status: deprecated`; capability keys drawn from a known set so typos fail instead of silently reading as unsupported.
- **Freshness**: runs the generator in memory and asserts the five checked-in artifacts match byte-for-byte, with a failure message naming `bin/generate_llm_registry`. Subsumes the existing locale-key spec and extends the guarantee to the initializer template and setup docs.

**Deliberate exclusion:** CI does not fail when a `retirement_date` passes. Time-based CI failures break unrelated PRs. Overdue retirements are surfaced by `/model-check` and the smoke runner summary instead.

## Component 3: Capability-matrix smoke runner

`bin/smoke` (wrapping `script/smoke.rb`) replaces `bin/smoke_llm_models`, `bin/smoke_embedding_models`, `bin/probe_structured_outputs`, `bin/probe_streaming_tool_calls`, and `bin/probe_bedrock_stream_transport`. Clean cut: old scripts are deleted, `CONTRIBUTING.md` smoke section rewritten. Selector parsing and credential gating are written once (credential map carried over from the current scripts). Providers without credentials are skipped with a clear note.

### Selection and scoping

```bash
bin/smoke anthropic_claude_5_sonnet                    # one model, full matrix
bin/smoke anthropic                                    # provider prefix
bin/smoke ALL
bin/smoke --stale [days]                               # positively claimed, recordable capabilities missing a fresh successful observation
bin/smoke x_ai --only batch_inference                  # capability-scoped
bin/smoke bedrock_claude_5_sonnet --only streaming --iterations 5
```

Capability-specific options hang off `--only` (e.g. `--iterations` for streaming, `--timeout` for batch). `--skip batch` exists because batch polling dominates wall-clock time.

### Skip semantics and the add-model gate

Skips must not be able to masquerade as a passing result:

- **Explicitly selected models** (named by key on the command line): any `SKIP`, `TIMEOUT`, or required check left unexecuted (missing credentials included) exits nonzero, and `--record` never records the affected capabilities, since there is no successful observation to record. This is what makes `/model-add`'s smoke step a real gate; a new model cannot pass it without credentials for its provider.
- **Pattern and sweep selections** (provider prefix, `ALL`, `--stale`): providers without credentials are skipped with a clear note and do not fail the run. `--strict` upgrades sweeps to the explicit-selection policy for a future scheduled CI job.

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

### Claim-aware verdicts

Every check reports one of five statuses: `PASS`, `FAIL`, `NOTE`, `SKIP`, or `TIMEOUT`. A verdict is claim-aware, not a plain pass/fail:

- **Claimed `true` that fails**: `FAIL`, nonzero exit for an explicitly selected model.
- **Claimed `true` that passes**: `PASS`. Only a `PASS` from a check with a concrete, checkable pass criterion (a hard oracle, e.g. an exact expected reply, a nonce that must appear in the response, tool-call arguments that must parse as a hash) is eligible for `--record`. A softer `PASS`, such as the `structured_outputs` JSON-tool fallback path (it can produce valid JSON even on a model with no native structured-output support), is tagged not recordable.
- **Claimed `false`**: the cheap capabilities (`temperature`, `structured_outputs`) are probed anyway on every run; the more expensive ones (`native_tool_use`, `streaming`, `streaming_tool_calls`, `batch_inference`, `images`, `pdfs`, `provider_managed_tools`) are skipped by default and only probed when named explicitly via `--only`. Either way, a claimed-false capability that passes is downgraded to `NOTE: claimed unsupported but appears to work` rather than `PASS`: it means the manifest's claim is stale, not that anything has been verified. `NOTE` never fails the run and is never recordable.

A `FAIL` is written only to the terminal, never to a stored file. It is diagnostic evidence worth a maintainer's attention, not proof the model lacks the capability: the same `FAIL` can come from a transient provider error, an expired fixture, or a bug in the check itself, as easily as from a real regression. No automated process treats a `FAIL`, or any other stored or terminal result, as confirmation that a capability is unsupported or as having "verified" a manifest claim either way; deciding what a `FAIL` means, and whether to act on it, is a human judgment call.

### Output and recording

A per-model matrix showing every capability's status is printed to the terminal (with per-model progress streamed as a multi-model run proceeds); `--format json` emits the same information for machine consumption. `--record` writes only the capabilities that scored a recordable `PASS` this run into `model_smoke_results/<provider>.json`, one file per provider, each entry holding the claimed value, `"result": "pass"`, and a `checked_at` timestamp. `--record` never opens or edits `model_manifest/*.rb`, and it never writes a `FAIL`, `NOTE`, `SKIP`, or `TIMEOUT` result anywhere.

Writing is additive, not a snapshot: an existing provider file is merged capability by capability, so anything this run did not re-observe as a recordable pass, whether because it was not selected, or because it failed, timed out, or only scored a softer or claimed-false `NOTE` this time, keeps whatever was already on file. A later run's failure therefore never withdraws a previously recorded success. Withdrawing or acting on stored evidence is a maintainer decision made by editing `model_smoke_results/` directly; it is not something any run of `bin/smoke` does for itself. Models within a provider run sequentially; providers run in parallel threads.

## Component 4: Claude workflow skills

Three commands in `.claude/commands/`, alongside `release-prep.md`. Shared contract: research, report, confirm, act. No file edits before an approved concrete proposal. One PR per concern. All PRs are drafts.

### /model-check [hint]

The patrol. Bare invocation asks "anything specific that prompted this, or general sweep?" Arguments scope it: a provider, a concern (`pricing openai`), a pasted URL, or a rumor ("heard Gemini 3 dropped").

1. Gather from manifest reference URLs, provider list-models APIs where available, and web search. A user-supplied URL is used directly and added to that provider's `references` for next time.
2. Cross-reference against the manifest: models upstream but not here; pricing differences; announced deprecations not recorded; retirement dates near or past; models whose recordable capabilities have stale or missing successful observations in `model_smoke_results/`; deprecated models approaching retirement with neither `replacement_key` nor `migration_note`.
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

1. A one-time extraction script bootstrapped the original YAML manifest from the hand-written registry (including copying every current `en.yml` display name verbatim into `display_name` fields), then was deleted.
2. A temporary equivalence spec asserted the generated `Raif.default_llms` hash equaled the hand-written one (every key, cost, and setting), and that the generated locale sections reproduced the `raif.model_names` / `embedding_model_names` entries exactly, before the hand-written data was removed. This guarded against an unintended user-facing rename migration.
3. Capability facts not modeled before this system (per-model images and PDFs) started as researched claims with no stored evidence behind them yet. There was no bulk pass that seeded a verification block for them, because no such block exists: evidence for them accumulates independently, one `bin/smoke --record` run at a time, into `model_smoke_results/*.json`, entirely separate from the manifest that declares the claim.
4. A second migration then replaced the YAML manifest with the constrained Ruby DSL described in Component 1. A normalized equivalence check compared every YAML provider file against its Ruby rewrite (same keys, pricing, capabilities, and lifecycle) before the YAML files were deleted, and the generator's freshness spec was extended so the checked-in artifacts must still match the Ruby manifest byte-for-byte.

### Ongoing coverage

- Manifest validity and freshness specs run in normal CI; no live APIs.
- Generator: unit specs against a small fixture manifest (`spec/fixtures/model_manifest/*.rb`).
- Manifest DSL: unit specs asserting the restricted evaluation context accepts only `provider` and `embeddings` declarations and raises on anything else, and that a malformed model declaration (e.g. `key:` combined with `endpoints:`) raises instead of silently producing a partial entry.
- Smoke runner logic (selector parsing, credential gating, claim-aware verdicts, hard-oracle recordability, `--stale` selection against the observation store): unit specs with `TestLlm` and fixture observation files. Live-API paths remain manually invoked.
- Smoke observation store: unit specs covering schema-version validation, merge-not-replace recording, and staleness/claim-mismatch detection.
- Deprecation warning and admin badge: standard specs.
- The existing provider specs and VCR cassettes are untouched; request/response behavior does not change.

### Delivery

Two phases, each ordered so every commit leaves the suite green, superseding the single-branch order originally proposed below:

1. **Smoke trust, manifest still YAML**: claim-aware verdicts and hard oracles in the check logic; numeric CLI option validation; a read-only smoke-observation store under `model_smoke_results/`; a post-run recorder that only ever writes to that store, never to manifest source; `--stale` selection driven by the observation store; removal of the (now unused) embedded `verification` field from the YAML manifest loader.
2. **Ruby manifest migration**: the constrained DSL; a normalized YAML-vs-Ruby equivalence check; replacement of `model_manifest/*.yml` with `model_manifest/*.rb`; generator and freshness-spec updates for exact whole-file output; regeneration of all five checked-in artifacts; deletion of the equivalence scaffolding once the Ruby manifest is authoritative.
3. **Workflow and documentation**: the three Claude command files, `CONTRIBUTING.md`, `CLAUDE.md`, `CHANGELOG.md`, the customization and streaming docs, and this design document, updated to describe the system as built.

The originally proposed single-branch order was:

1. Manifest files + extraction script + equivalence spec (the hand-written registry data is snapshotted to a spec fixture so the equivalence spec has a stable comparison target).
2. Generator + freshness/validity specs + generated artifacts (generation replaces the hand-written content of the runtime registry; equivalence spec compares against the fixture).
3. Delete equivalence scaffolding, the fixture snapshot, and the extraction script.
4. Smoke runner + delete old scripts + CONTRIBUTING update.
5. Deprecation runtime + admin badge.
6. The three command files.

That order shipped the smoke runner writing straight back into the manifest, which the smoke-trust rework above replaced before the Ruby DSL migration landed.

## Out of scope for v1

- Scheduled CI smoke runs and provider API keys as repo secrets (design keeps the door open: JSON output, nonzero exits).
- Automatic pricing feeds; pricing changes flow through `/model-check` research.
- Behavioral gating of deprecated models.
- Modeling context-window size (only `max_completion_tokens` exists today; unchanged).
