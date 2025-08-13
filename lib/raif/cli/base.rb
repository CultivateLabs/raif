# frozen_string_literal: true

module Raif
  module CLI
    class Base
      attr_reader :args, :options

      def initialize(args = [])
        @args = args
        @options = {}
      end

    protected

      def find_rails_root
        current = Dir.pwd

        until File.exist?(File.join(current, "config", "environment.rb"))
          parent = File.dirname(current)
          if parent == current
            puts "Error: Could not find Rails application root"
            puts "Please run this command from within a Rails application directory"
            exit 1
          end

          current = parent
        end

        current
      end

      def load_rails_application
        rails_root = find_rails_root
        Dir.chdir(rails_root)
        require File.join(rails_root, "config", "environment")
      end
    end
  end
end
