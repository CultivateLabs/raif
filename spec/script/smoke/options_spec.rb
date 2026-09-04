# frozen_string_literal: true

require "rails_helper"
require Raif::Engine.root.join("script/smoke/options")

RSpec.describe Smoke do
  describe ".validate_options!" do
    let(:parser) { OptionParser.new }

    it "rejects zero iterations" do
      options = { iterations: 0, batch_timeout: 60, stale_days: nil }
      expect { Smoke.validate_options!(options, parser) }
        .to raise_error(SystemExit)
    end

    it "rejects zero batch timeout" do
      options = { iterations: 1, batch_timeout: 0, stale_days: nil }
      expect { Smoke.validate_options!(options, parser) }
        .to raise_error(SystemExit)
    end

    it "rejects negative stale days" do
      options = { iterations: 1, batch_timeout: 60, stale_days: -1 }
      expect { Smoke.validate_options!(options, parser) }
        .to raise_error(SystemExit)
    end

    it "accepts valid positive iterations" do
      options = { iterations: 1, batch_timeout: 60, stale_days: nil }
      expect { Smoke.validate_options!(options, parser) }
        .not_to raise_error
    end

    it "accepts valid positive batch timeout" do
      options = { iterations: 1, batch_timeout: 600, stale_days: nil }
      expect { Smoke.validate_options!(options, parser) }
        .not_to raise_error
    end

    it "accepts zero stale days" do
      options = { iterations: 1, batch_timeout: 60, stale_days: 0 }
      expect { Smoke.validate_options!(options, parser) }
        .not_to raise_error
    end

    it "accepts nil stale days" do
      options = { iterations: 1, batch_timeout: 60, stale_days: nil }
      expect { Smoke.validate_options!(options, parser) }
        .not_to raise_error
    end

    it "accepts positive stale days" do
      options = { iterations: 1, batch_timeout: 60, stale_days: 30 }
      expect { Smoke.validate_options!(options, parser) }
        .not_to raise_error
    end
  end
end
