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
