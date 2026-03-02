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
Use this helper to quickly verify live model calls from the dummy app:

```bash
bin/smoke_llm_models ALL
bin/smoke_llm_models anthropic bedrock
bin/smoke_llm_models anthropic_claude_4_6_opus bedrock_claude_4_6_opus
AWS_PROFILE=your-profile AWS_REGION=us-east-1 bin/smoke_llm_models bedrock
bin/smoke_llm_models open_ai_responses --prompt "Reply with exactly: ping"
```

Notes:
- Anthropic requires `ANTHROPIC_API_KEY`.
- OpenAI requires `OPENAI_API_KEY`.
- OpenRouter requires `OPEN_ROUTER_API_KEY` (or `OPENROUTER_API_KEY`).
- Google requires `GOOGLE_AI_API_KEY` (or `GOOGLE_API_KEY`).
- Bedrock requires valid AWS credentials and model access.
- To avoid metadata lookup delays locally, `bin/smoke_llm_models` sets `AWS_EC2_METADATA_DISABLED=true` if not already set.
- Use `bin/smoke_llm_models --list` to print all registered model keys.
- `RAIF_SMOKE_MODELS` can still be used as a comma-separated fallback list when no positional selectors are provided.

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
