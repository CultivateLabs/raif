# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in raif.gemspec.
gemspec

gem "puma"
gem "pg"
gem "mysql2"
gem "guard-rspec", require: false
gem "factory_bot_rails"
gem "debug", platforms: [:mri]
gem "rspec-rails"
gem "rubocop-shopify"
gem "i18n-tasks"
gem "erb_lint"
gem "capybara"
gem "propshaft"
gem "importmap-rails"
gem "stimulus-rails"
gem "cuprite"
gem "webmock"
gem "vcr"
gem "yard"
# Pinned below 4.24: its ModelWrapper#column_defaults prefers the raw DB default over
# the model's, which strips the label off every enum-backed integer column
# (`default("text")` becomes `default(0)`).
gem "annotaterb", "~> 4.23.0"
gem "openssl", "4.0.2"
