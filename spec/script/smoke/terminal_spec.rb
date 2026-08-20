# frozen_string_literal: true

require "rails_helper"
require Raif::Engine.root.join("script/smoke/terminal")

RSpec.describe Smoke::Terminal do
  describe ".paint" do
    it "wraps text in the color's ANSI code and a reset when enabled" do
      expect(described_class.paint("hi", :green, enabled: true)).to eq("\e[32mhi\e[0m")
    end

    it "returns the plain text unchanged when disabled" do
      expect(described_class.paint("hi", :green, enabled: false)).to eq("hi")
    end

    it "maps each supported color to its ANSI code" do
      expect(described_class.paint("x", :red, enabled: true)).to eq("\e[31mx\e[0m")
      expect(described_class.paint("x", :yellow, enabled: true)).to eq("\e[33mx\e[0m")
      expect(described_class.paint("x", :cyan, enabled: true)).to eq("\e[36mx\e[0m")
      expect(described_class.paint("x", :bold, enabled: true)).to eq("\e[1mx\e[0m")
      expect(described_class.paint("x", :dim, enabled: true)).to eq("\e[2mx\e[0m")
    end

    it "derives enabled from colors_enabled?(stream) when not given explicitly" do
      tty_stream = instance_double(IO, tty?: true)

      expect(described_class.paint("hi", :green, stream: tty_stream)).to eq("\e[32mhi\e[0m")
    end
  end

  describe ".status_paint" do
    it "paints pass green" do
      expect(described_class.status_paint("PASS", :pass, enabled: true)).to eq("\e[32mPASS\e[0m")
    end

    it "paints fail red" do
      expect(described_class.status_paint("FAIL", :fail, enabled: true)).to eq("\e[31mFAIL\e[0m")
    end

    it "paints timeout red" do
      expect(described_class.status_paint("TIMEOUT", :timeout, enabled: true)).to eq("\e[31mTIMEOUT\e[0m")
    end

    it "paints skip yellow" do
      expect(described_class.status_paint("SKIP", :skip, enabled: true)).to eq("\e[33mSKIP\e[0m")
    end

    it "paints note cyan" do
      expect(described_class.status_paint("NOTE", :note, enabled: true)).to eq("\e[36mNOTE\e[0m")
    end

    it "leaves an unrecognized status plain even when enabled" do
      expect(described_class.status_paint("WEIRD", :weird, enabled: true)).to eq("WEIRD")
    end

    it "returns the plain label unchanged when disabled" do
      expect(described_class.status_paint("PASS", :pass, enabled: false)).to eq("PASS")
    end
  end

  describe ".colors_enabled?" do
    after { described_class.instance_variable_set(:@no_color_flag, nil) }

    it "is true for a tty stream with NO_COLOR unset and colors not disabled" do
      tty_stream = instance_double(IO, tty?: true)

      expect(described_class.colors_enabled?(tty_stream)).to eq(true)
    end

    it "is false for a non-tty stream" do
      non_tty_stream = instance_double(IO, tty?: false)

      expect(described_class.colors_enabled?(non_tty_stream)).to eq(false)
    end

    it "is false when NO_COLOR is set, even on a tty" do
      tty_stream = instance_double(IO, tty?: true)

      with_env("NO_COLOR" => "1") do
        expect(described_class.colors_enabled?(tty_stream)).to eq(false)
      end
    end

    it "is false after disable_colors!, even on a tty" do
      tty_stream = instance_double(IO, tty?: true)
      described_class.disable_colors!

      expect(described_class.colors_enabled?(tty_stream)).to eq(false)
    end

    def with_env(vars)
      previous = vars.keys.to_h { |key| [key, ENV[key]] }
      vars.each { |key, value| ENV[key] = value }
      yield
    ensure
      previous.each { |key, value| ENV[key] = value }
    end
  end

  describe ".format_duration" do
    it "formats a sub-hour duration as MM:SS" do
      expect(described_class.format_duration(65)).to eq("01:05")
    end

    it "formats an hour-plus duration as H:MM:SS" do
      expect(described_class.format_duration(3700)).to eq("1:01:40")
    end

    it "zero-pads seconds under a minute" do
      expect(described_class.format_duration(7)).to eq("00:07")
    end

    it "rounds a fractional number of seconds" do
      expect(described_class.format_duration(65.6)).to eq("01:06")
    end
  end

  describe ".confirm?" do
    it "prints the question with a [y/N] suffix to stderr" do
      allow($stdin).to receive(:gets).and_return("n\n")

      expect { described_class.confirm?("Continue?") }.to output("Continue? [y/N] ").to_stderr
    end

    it "returns true for y" do
      allow($stdin).to receive(:gets).and_return("y\n")

      expect(described_class.confirm?("Continue?")).to eq(true)
    end

    it "returns true for yes, case-insensitively" do
      allow($stdin).to receive(:gets).and_return("YES\n")

      expect(described_class.confirm?("Continue?")).to eq(true)
    end

    it "returns false for no" do
      allow($stdin).to receive(:gets).and_return("n\n")

      expect(described_class.confirm?("Continue?")).to eq(false)
    end

    it "returns false for a blank line" do
      allow($stdin).to receive(:gets).and_return("\n")

      expect(described_class.confirm?("Continue?")).to eq(false)
    end

    it "returns false on EOF (gets returns nil)" do
      allow($stdin).to receive(:gets).and_return(nil)

      expect(described_class.confirm?("Continue?")).to eq(false)
    end
  end
end
