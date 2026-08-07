# frozen_string_literal: true

require "rails_helper"
require "raif/cli"

RSpec.describe Raif::CLI::Runner do
  it "prints the version" do
    result = run_raif_cli("version")

    expect(result.exit_code).to eq(0)
    expect(result.stdout).to include("Raif #{Raif::VERSION}")
  end

  it "lists the commands when asked for help" do
    result = run_raif_cli("help")

    expect(result.exit_code).to eq(0)
    Raif::CLI::COMMANDS.each_key { |command| expect(result.stdout).to include(command) }
  end

  it "shows help when given no command at all" do
    result = run_raif_cli

    expect(result.exit_code).to eq(0)
    expect(result.stdout).to include("Usage: raif COMMAND [options]")
  end

  it "exits non-zero on an unknown command" do
    result = run_raif_cli("summarise-everything")

    expect(result.exit_code).to eq(1)
    expect(result.stdout).to include("Unknown command: summarise-everything")
  end

  # The dispatch table and the help text are written out separately, so one can gain a
  # command the other never mentions.
  it "dispatches every command it advertises" do
    documented = Raif::CLI::COMMANDS.keys - ["help", "version"]

    documented.each do |command|
      result = run_raif_cli(command, "--help")

      expect(result.stdout).to include("Usage: raif #{command}"), "expected `#{command} --help` to print its own usage"
    end
  end
end
