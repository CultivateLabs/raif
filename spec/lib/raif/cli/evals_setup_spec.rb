# frozen_string_literal: true

require "rails_helper"
require "raif/cli"
require "rails/generators"

RSpec.describe Raif::CLI::EvalsSetup do
  # The generator name this command delegates to is a string nothing else checks.
  it "invokes the evals setup generator" do
    cli = described_class.new([])
    allow(cli).to receive(:load_rails_application)
    allow(Rails::Generators).to receive(:invoke)

    cli.run

    expect(Rails::Generators).to have_received(:invoke).with("raif:evals:setup", [])
  end

  it "passes positional arguments through to the generator" do
    cli = described_class.new(["some_argument"])
    allow(cli).to receive(:load_rails_application)
    allow(Rails::Generators).to receive(:invoke)

    cli.run

    expect(Rails::Generators).to have_received(:invoke).with("raif:evals:setup", ["some_argument"])
  end

  # The command declares only -h, so anything else is a typo rather than a generator option.
  it "rejects an unrecognized option" do
    cli = described_class.new(["--force"])
    allow(cli).to receive(:load_rails_application)

    expect { cli.run }.to raise_error(OptionParser::InvalidOption)
  end
end
