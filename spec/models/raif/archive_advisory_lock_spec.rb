# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::ArchiveAdvisoryLock do
  describe ".acquire" do
    def stub_connection(connection)
      allow(Raif::ModelCompletion).to receive(:connection).and_return(connection)
      connection
    end

    it "runs the block with the lock held, releases it, and returns true" do
      connection = stub_connection(Raif::ModelCompletion.connection)
      allow(connection).to receive(:get_advisory_lock).and_call_original
      allow(connection).to receive(:release_advisory_lock).and_call_original

      ran = false
      expect(described_class.acquire { ran = true }).to be(true)

      expect(ran).to be(true)
      expect(connection).to have_received(:get_advisory_lock)
      expect(connection).to have_received(:release_advisory_lock)
    end

    it "returns false without running the block when another session holds the lock" do
      connection = stub_connection(Raif::ModelCompletion.connection)
      allow(connection).to receive(:get_advisory_lock).and_return(false)
      allow(connection).to receive(:release_advisory_lock)

      ran = false
      expect(described_class.acquire { ran = true }).to be(false)

      expect(ran).to be(false)
      expect(connection).not_to have_received(:release_advisory_lock)
    end

    it "releases the lock when the block raises" do
      connection = stub_connection(Raif::ModelCompletion.connection)
      allow(connection).to receive(:release_advisory_lock).and_call_original

      expect { described_class.acquire { raise IOError, "boom" } }.to raise_error(IOError)

      expect(connection).to have_received(:release_advisory_lock)
    end

    it "runs unguarded with a warning on adapters without advisory lock support" do
      # Shaped like a real non-supporting adapter (e.g. SQLite):
      # AbstractAdapter defines get_advisory_lock as a nil-returning stub on
      # EVERY adapter, so support must be detected via
      # supports_advisory_locks?, never respond_to? (a nil return would
      # otherwise read as "lock busy" and silently skip the work forever).
      stub_connection(
        double(
          "adapter without advisory lock support",
          supports_advisory_locks?: false,
          get_advisory_lock: nil,
          release_advisory_lock: nil
        )
      )
      allow(Rails.logger).to receive(:warn).and_call_original

      ran = false
      expect(described_class.acquire { ran = true }).to be(true)

      expect(ran).to be(true)
      # The exclusion between archive runs and partition purges silently not
      # applying is exactly the kind of thing an operator needs to hear about.
      expect(Rails.logger).to have_received(:warn).with(/advisory lock/)
    end
  end
end
