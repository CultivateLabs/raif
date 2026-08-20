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

### Manual LLM Smoke Tests

`bin/smoke` verifies live models against the capabilities claimed in `model_manifest/*.yml`:

```bash
bin/smoke anthropic_claude_5_sonnet          # one model, full capability matrix
bin/smoke anthropic bedrock                  # provider sweeps
bin/smoke ALL                                # everything with credentials available
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
