# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Configuration do
  describe "#validate!" do
    describe "model_completion_authorizer" do
      around do |example|
        original = Raif.config.model_completion_authorizer
        example.run
      ensure
        Raif.config.model_completion_authorizer = original
      end

      it "allows nil" do
        Raif.config.model_completion_authorizer = nil
        expect { Raif.config.validate! }.to_not raise_error
      end

      it "allows and freezes a callable" do
        authorizer = ->(llm:, source:) {}
        Raif.config.model_completion_authorizer = authorizer

        expect { Raif.config.validate! }.to_not raise_error
        expect(authorizer).to be_frozen
      end

      it "raises for a non-callable value" do
        Raif.config.model_completion_authorizer = "not callable"

        expect { Raif.config.validate! }.to raise_error(
          Raif::Errors::InvalidConfigError,
          /model_completion_authorizer must be nil or respond to :call/
        )
      end
    end
  end
end
