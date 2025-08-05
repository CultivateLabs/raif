# frozen_string_literal: true

require "optparse"
require_relative "base"

module Raif
  module CLI
    class EvalsSetup < Base
      def run
        OptionParser.new do |opts|
          opts.banner = "Usage: raif evals:setup [options]"
          opts.on("-h", "--help", "Show this help message") do
            puts opts
            exit
          end
        end.parse!(args)

        # Load Rails application to use generators
        load_rails_application

        # Invoke the Rails generator
        require "rails/generators"
        Rails::Generators.invoke("raif:evals:setup", args)
      end
    end
  end
end
