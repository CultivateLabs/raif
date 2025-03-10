# frozen_string_literal: true

require_relative "lib/raif/version"

Gem::Specification.new do |spec|
  spec.name        = "raif"
  spec.version     = Raif::VERSION
  spec.authors     = ["Ben Roesch"]
  spec.email       = ["ben@cultivatelabs.com"]
  spec.homepage    = "https://github.com/cultivatelabs/raif"
  spec.summary     = "Ruby AI Framework"
  spec.description = "Ruby AI Framework"
  spec.license     = "MIT"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/cultivatelabs/raif"
  spec.metadata["changelog_uri"] = "https://github.com/cultivatelabs/raif/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "aws-sdk-bedrock"
  spec.add_dependency "aws-sdk-bedrockruntime"
  spec.add_dependency "faraday"
  spec.add_dependency "json-schema"
  spec.add_dependency "loofah"
  spec.add_dependency "pagy"
  spec.add_dependency "rails", ">= 7.1"
  spec.add_dependency "reverse_markdown"
  spec.add_dependency "ruby-openai"
  spec.add_dependency "simple_form"
end
