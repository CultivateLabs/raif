# Model Check

Patrol raif's model registry for drift against provider reality. Arguments (optional): a provider name, a concern ("pricing openai"), a URL, or a free-text tip. With no arguments, ask first: "Anything specific that prompted this, or general sweep?"

Rules that apply to every step:
- Research first, report second, act only after explicit approval. Never edit files before the user picks items to act on.
- One PR-sized branch per concern, suggested and created only with the user's agreement. NEVER run `git commit`, `git push`, or open a PR yourself: propose each commit (staged file list plus drafted message) and act only after the user approves it.
- No em dashes or en dashes in anything you write (CHANGELOG, commits, docs). No AI attribution in commits. Keep wording generic to raif.
- Provider documentation plus the user's approved proposal determines manifest truth. Smoke output is supporting runtime evidence. Never change a declared capability solely because a generic API request failed.

Steps:
1. Read `lib/raif/model_manifest/definitions/*.rb`. Note each provider's `references` URLs.
2. Gather, scoped by the user's hint when given: fetch the reference URLs (WebFetch), search the web for announcements since the newest `added_on`, and where a provider has a public list-models API and a key is configured, list it (OpenAI GET /v1/models, Anthropic GET /v1/models, xAI GET /v1/models, OpenRouter GET /api/v1/models, Google GET /v1beta/models).
3. Cross-reference against the manifest and report findings in these groups, each item with its source cited:
   - models available upstream but absent from the manifest
   - pricing differences (manifest per-million vs published)
   - pricing annotations needing re-verification: entries whose `pricing[:valid_until]` is past or within 30 days, and entries whose `pricing[:note]` describes a promotion the provider no longer documents
   - announced deprecations or retirements not recorded in lifecycle fields
   - recorded retirement_dates within 60 days or past
   - deprecated models whose replacement_key is itself deprecated, or with neither replacement_key nor migration_note
   - models with unverified or stale capabilities (per `bin/smoke --stale 30`'s selection logic: read `model_smoke_results/*.json` for missing or old successful observations against positively claimed, recordable capabilities; do not run bin/smoke or hit live APIs for this)
4. Ask which findings to act on (AskUserQuestion, multiSelect). Whenever any provider under check has models with missing or stale smoke observations, the question MUST include a "Smoke <provider> models (bin/smoke --record)" option alongside the other findings, even when no other finding needs action. This is the only place in the workflow where a live smoke run is offered, so it is never dropped to keep the list short.
5. For each approved finding, ask: handle here sequentially, or write a handoff doc per concern to `docs/handoffs/` (Goal / Current State / Key Decisions / Next Steps format) for parallel sessions.
6. Acting on a finding in-session:
   - smoke run (missing or stale observations): before running anything, state the scope in chat: the selectors (exact keys, a provider prefix such as `google` or `x_ai`, or `--stale 30`; OpenAI needs both `open_ai` and `open_ai_responses` since the first prefix excludes responses keys; see `bin/smoke --help`), how many models that covers, that it spends real API credits, that batch_inference probes poll for up to 10 minutes each, and that provider-managed image_generation is skipped unless run with `--only provider_managed_tools`. Missing credentials for that provider block the run; say so instead of running. On approval run `bin/smoke <selectors> --record`; `--record` writes only hard-oracle passes to `model_smoke_results/<provider>.json` and never edits the manifest. Present the full matrix. FAIL and NOTE are investigation prompts, not manifest edits: research each against provider documentation, propose a specific correction with citations, edit only after approval, then re-smoke that capability with `bin/smoke <key> --only <capability> --record`. Stage the updated `model_smoke_results/<provider>.json` together with whatever manifest change it accompanies in this session (pricing, deprecation, or addition) so the evidence lands with the change it verifies; only when nothing else changed, propose it as its own commit on the current branch
   - pricing update: edit the manifest pricing (when the published rate is promotional or time-limited, write the published rate and add `note:` and, if an end date is documented, `valid_until: Date.new(...)`), run `bundle exec rspec spec/lib/raif/model_manifest_validity_spec.rb`, add a CHANGELOG bullet, suggest a `model-pricing-<provider>` branch, and propose the commit (diff, files to stage, drafted message) for the user to approve
   - new model: switch to the /model-add workflow with what you learned
   - deprecation/retirement: switch to the /model-retire workflow
   - if the user supplied a URL that proved useful, add it to that provider's `references` in the manifest
