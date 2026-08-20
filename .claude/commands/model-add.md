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
