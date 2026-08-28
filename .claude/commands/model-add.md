# Model Add

Add one new model to raif, end to end. Argument: a model name, provider + name, or an announcement URL.

Rules: research first and confirm before editing; the smoke gate is mandatory and cannot be skipped; NEVER run `git commit`, `git push`, or open a PR yourself: propose branches and commits and act only after the user approves that specific proposal; no em or en dashes anywhere; no AI attribution in commit messages.

Provider documentation plus the user's approved proposal determines manifest truth. Smoke output is supporting runtime evidence. Never change a declared capability solely because a generic API request failed.

Steps:
1. Research the model from the argument plus the provider's `references` URLs in `lib/raif/model_manifest/definitions/<provider>.rb`: API name, per-million pricing, max output tokens, capabilities (temperature parameter support, structured outputs, tool calling, streaming, batch API availability, image/PDF input, provider-managed tools).
2. Propose a complete manifest entry in chat: every field, with a source citation per fact and every unverifiable guess flagged as a guess (for example "no batch API documented, claiming batch_inference: false"). When the provider documents promotional, temporary, or threshold-dependent pricing, include the optional pricing keys: `note:` describing the situation and, when the provider states an end date, `valid_until: Date.new(...)`. For OpenAI models, propose both endpoints (or responses-only). Ask for approval.
3. On approval:
   - if the session is on main or an unrelated branch, suggest `model-add-<key>` off main and create it once the user agrees; if already on a suitable branch, say so and continue
   - add the entry to `lib/raif/model_manifest/definitions/<provider>.rb` (status: active, added_on: today, display_name following the existing naming pattern for that provider)
   - run `bundle exec rspec spec/lib/raif/model_manifest_validity_spec.rb spec/models/raif/llm_spec.rb`
4. Smoke it (mandatory): run `bin/smoke` with the newly added model's actual key and `--record`. Missing credentials, SKIP, or TIMEOUT blocks completion. If the model declares the image_generation provider-managed tool, a full run skips it as expensive and reports provider_managed_tools as SKIP (nonzero exit for an explicitly selected model); run a follow-up `bin/smoke <key> --only provider_managed_tools --record` to actually exercise and verify image generation.
5. Present the complete matrix. A hard-oracle PASS may be recorded in `model_smoke_results/`. FAIL and NOTE are investigation prompts, not automatic manifest edits. Research any discrepancy against official provider documentation, propose a specific correction with citations, and edit only after user approval. After any approved manifest edit, re-smoke the affected capability with `bin/smoke <key> --only <capability> --record`. Loop until the matrix matches the claims.
6. Add a CHANGELOG bullet under the current pre-release heading: "Added <display_name> (`<key>`)" plus notable capability caveats. Run `bundle exec rspec` and `bin/lint`.
7. Propose the commit: show the full diff, the smoke matrix, the exact files to stage, and a drafted commit message, then STOP. Commit only after the user approves the staged files and message. Push and PR remain separate approvals (PR body includes the smoke matrix as evidence).
