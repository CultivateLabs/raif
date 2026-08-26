# Model Retire

Deprecate or remove a model. Argument: a model key, optionally with a provider announcement URL.

Rules: confirm the provider's announcement before editing; NEVER run `git commit`, `git push`, or open a PR yourself: propose branches and commits and act only after the user approves that specific proposal; no em or en dashes; no AI attribution in commit messages.

Provider documentation plus the user's approved proposal determines manifest truth. Smoke output is supporting runtime evidence. Never change a declared capability solely because a generic API request failed.

Decide the mode first:
- Provider announced end of life but the model still works: DEPRECATE.
- Retirement date reached or the API already rejects it: REMOVE.
Confirm the mode with the user. Deprecation and removal decisions always rest with the user; do not act on either mode without their explicit confirmation.

DEPRECATE:
1. Verify the announcement (fetch the provider's deprecations URL from the manifest references; cite it).
2. Set lifecycle on the manifest entry:
   ```ruby
   lifecycle: {
     status: :deprecated,
     deprecated_on: Date.new(2026, 8, 24),
     retirement_date: Date.new(2026, 12, 1),
     replacement_key: :replacement_model
   }
   ```
   `replacement_key` must be an active key. When the provider names no successor, ask the user: propose the closest alternative with caveats stated, or set migration_note explaining there is no direct replacement.
3. `bin/generate_llm_registry`, then `bundle exec rspec`.
4. CHANGELOG bullet: "Deprecated `<key>`; scheduled for removal after <retirement_date>. <replacement or note>."
5. Suggest branch `model-deprecate-<key>` (create it once the user agrees, unless already on a suitable branch), then propose the commit: show the diff, the files to stage, and a drafted message, and STOP. Commit only after the user approves.

REMOVE:
1. Set `status: :retired` on the manifest entry (keep all lifecycle history; never delete the entry).
2. `bin/generate_llm_registry`.
3. Find residue: `grep -rn "<key>" spec/ lib/ app/ docs/ vcr_cassettes/`. Migrate specs that used the key to the replacement; regenerate or edit affected VCR cassettes the way the repo has done before (see git log for prior removals, for example cec8728d).
4. `bundle exec rspec` and `bin/lint` until green.
5. CHANGELOG bullet prefixed "**Breaking change**:" naming the key, the provider's retirement notice (cite URL), and the replacement guidance.
6. Suggest branch `model-retire-<key>` (create it once the user agrees, unless already on a suitable branch), then propose the commit: show the diff, the files to stage, and a drafted message, and STOP. Commit only after the user approves.
