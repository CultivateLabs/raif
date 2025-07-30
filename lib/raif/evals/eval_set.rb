# frozen_string_literal: true

require "raif/evals/eval_sets/expectations"

module Raif
  module Evals
    class EvalSet
      include Raif::Evals::EvalSets::Expectations

      attr_reader :current_eval, :output

      def initialize(output: $stdout)
        @output = output
      end

      class << self
        attr_reader :setup_block
        attr_reader :teardown_block

        def inherited(subclass)
          subclass.instance_variable_set(:@evals, [])
          super
        end

        def evals
          @evals ||= []
        end

        def eval(description, &block)
          evals << { description: description, block: block }
        end

        def setup(&block)
          @setup_block = block
        end

        def teardown(&block)
          @teardown_block = block
        end

        def run(output: $stdout)
          new(output: output).run
        end
      end

      def run
        results = []

        self.class.evals.each do |eval_definition|
          @current_eval = Eval.new(description: eval_definition[:description])

          output.puts "Running: #{eval_definition[:description]}"

          ActiveRecord::Base.transaction do
            instance_eval(&self.class.setup_block) if self.class.setup_block

            begin
              instance_eval(&eval_definition[:block])
            rescue => e
              output.puts Raif::Utils::Colors.red("  Error in eval block: #{e.message}")
              @current_eval.add_expectation_result(
                ExpectationResult.new(
                  description: "Eval block execution",
                  status: :error,
                  error: e
                )
              )
            ensure
              instance_eval(&self.class.teardown_block) if self.class.teardown_block
            end

            results << @current_eval

            raise ActiveRecord::Rollback
          end
        end

        results
      end

      def file(filename)
        path = File.join("raif_evals", "files", filename)
        if File.exist?(path)
          File.read(path)
        else
          raise "File #{filename} does not exist"
        end
      end

    end
  end
end
