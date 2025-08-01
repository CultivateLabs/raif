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