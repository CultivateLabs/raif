# frozen_string_literal: true

require_relative "lib/raif/version"

Gem::Specification.new do |spec|
  spec.name        = "raif"
  spec.version     = Raif::VERSION
  spec.authors     = ["Ben Roesch", "Brian Leslie"]
  spec.email       = ["ben@cultivatelabs.com", "brian@cultivatelabs.com"]
  spec.homepage    = "https://github.com/cultivatelabs/raif"
  spec.summary     = "Raif (Ruby AI Framework) is a Rails engine that helps you add AI-powered features to your Rails apps, such as tasks, conversations, and agents." # rubocop:disable Layout/LineLength
  spec.description = "Raif (Ruby AI Framework) is a Rails engine that helps you add AI-powered features to your Rails apps, such as tasks, conversations, and agents. It supports for multiple LLM providers including OpenAI, Anthropic Claude, and AWS Bedrock." # rubocop:disable Layout/LineLength
  spec.license     = "MIT"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/cultivatelabs/raif"
  spec.metadata["changelog_uri"] = "https://github.com/cultivatelabs/raif/blob/main/CHANGELOG.md"
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib,spec/support,exe}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }

  spec.add_dependency "aws-sdk-bedrockruntime"
  spec.add_dependency "event_stream_parser", ">= 1.0"
  spec.add_dependency "faraday", ">= 2.0"
  spec.add_dependency "json-schema", ">= 5.0"
  spec.add_dependency "loofah", ">= 2.21"
  spec.add_dependency "pagy"
  spec.add_dependency "rails", ">= 7.1"
  spec.add_dependency "reverse_markdown", ">= 2.0"
  spec.add_dependency "turbo-rails", ">= 2.0"
end
