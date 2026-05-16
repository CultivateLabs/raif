# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Concerns::LlmPromptCaching do
  describe ".enable_anthropic_prompt_caching" do
    it "sets anthropic_prompt_caching_enabled to true" do
      expect(Raif::TestCachedTask.anthropic_prompt_caching_enabled).to be(true)
    end

    it "defaults to false for tasks that don't enable it" do
      expect(Raif::TestTask.anthropic_prompt_caching_enabled).to be(false)
    end
  end

  describe ".enable_bedrock_prompt_caching" do
    it "sets bedrock_prompt_caching_enabled to true" do
      expect(Raif::TestCachedTask.bedrock_prompt_caching_enabled).to be(true)
    end

    it "defaults to false for tasks that don't enable it" do
      expect(Raif::TestTask.bedrock_prompt_caching_enabled).to be(false)
    end
  end
end
