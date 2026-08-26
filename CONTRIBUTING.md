# Contributing to Raif

## Development Environment Setup

### Setup Steps

1. **Fork and clone the repository:**
Fork the repository first, then clone it to your local machine:

```bash
git clone https://github.com/YOUR_USERNAME/raif.git
cd raif
git remote add upstream https://github.com/CultivateLabs/raif.git
git fetch upstream
git checkout main
```

2. **Install Ruby dependencies:**
```bash
bundle install
```

3. **Install JavaScript dependencies:**
```bash
yarn install
```

4. **Set up the database:**
```bash
bin/rails db:setup
```

## Running Tests

Raif uses RSpec for testing.

### Run All Tests
```bash
bundle exec rspec
```

### Run Tests with Guard (auto-reload)
```bash
bundle exec guard
```

### Model Pricing Annotations

A manifest entry's `pricing` hash accepts two optional keys alongside the required rates: `note` (a string documenting promotional or otherwise unusual pricing, for example a launch discount or a surcharge above a token threshold) and `valid_until` (a `Date` recording when a documented rate is scheduled to end). Neither affects the generated registry or runtime costs; they exist so `/model-check` can flag rates that need re-verification. A past `valid_until` is a review prompt, never a CI failure. Plain Ruby comments in manifest files are also welcome for anything the fields do not fit.

### Manual LLM Smoke Tests

`bin/smoke` verifies live models against the capabilities claimed in `model_manifest/*.rb`:

```bash
bin/smoke anthropic_claude_5_sonnet          # one model, full capability matrix
bin/smoke anthropic bedrock                  # provider sweeps
bin/smoke ALL                                # all LLM models with credentials available (use `embeddings` for embedding models)
bin/smoke --stale 30                         # models with missing or stale successful observations
bin/smoke x_ai --only batch_inference        # one capability
bin/smoke bedrock_claude_5_sonnet --only streaming_tool_calls --iterations 5
bin/smoke anthropic_claude_5_sonnet --record # record hard-oracle passes to model_smoke_results/
```

Notes:
- Explicitly selected models fail (nonzero exit) on SKIP or TIMEOUT; provider sweeps skip providers without credentials.
- Credentials: ANTHROPIC_API_KEY, OPENAI_API_KEY, OPEN_ROUTER_API_KEY (or OPENROUTER_API_KEY), GOOGLE_AI_API_KEY (or GOOGLE_API_KEY), XAI_API_KEY (or X_AI_API_KEY), AWS credentials plus AWS_REGION for Bedrock.
- `--record` stores only successful observations from checks with concrete pass criteria in `model_smoke_results/`. It never changes declared capabilities and never records FAIL, NOTE, SKIP, TIMEOUT, or CONSISTENT. A CONSISTENT cell means the provider rejected a claimed-false capability's forced parameter exactly as the manifest declares (agreement with the manifest, not a probe result to record). A later failure does not remove a previously recorded success; withdrawing or acting on evidence is a maintainer decision. Provider documentation and reviewed manifest changes remain authoritative. Commit the updated `model_smoke_results/*.json` files.
- `--stale DAYS` selects models whose positively claimed, recordable capabilities have missing or old successful observations.
- `bin/smoke --list` prints all model keys. `--format json` emits machine-readable results.
- `embeddings` selects all embedding models; an exact embedding key (e.g. `bin/smoke open_ai_text_embedding_3_small`) works too.
- A full `bin/smoke ALL` run makes live calls for every model, and batch_inference checks can poll for up to 10 minutes per model, so sweeps commonly add `--skip batch_inference`; per-model progress streams to stderr as each one finishes, with the final matrix printed at the end.
- On a terminal, a run selecting more than 10 models or including batch_inference checks asks for confirmation before it starts; pass `--yes` to skip the prompt (e.g. in scripts) and `--no-color` to disable colored output.

### Linting

Raif uses Rubocop, ERB Lint, and i18n-tasks for linting.

To run all linters:
```bash
bin/lint
```

Or to lint with auto-correct:
```bash
bin/lint -a
```
