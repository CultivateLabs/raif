# frozen_string_literal: true

require "raif/evals/eval_sets/expectations"
require "raif/evals/eval_sets/llm_judge_expectations"

module Raif
  module Evals
    class EvalSet
      include Raif::Evals::EvalSets::Expectations
      include Raif::Evals::EvalSets::LlmJudgeExpectations

      attr_reader :current_eval, :output, :results

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
        @results = []

        self.class.evals.each do |eval_definition|
          @results << run_eval(eval_definition)
        end

        @results
      end

      def run_eval(eval_definition)
        @current_eval = Eval.new(description: eval_definition[:description])

        output.puts "Running: #{eval_definition[:description]}"

        ActiveRecord::Base.transaction do
          instance_eval(&self.class.setup_block) if self.class.setup_block

          begin
            instance_eval(&eval_definition[:block])
          rescue => e
            output.puts Raif::Utils::Colors.red("  Error in eval block: #{e.message}")
            output.puts Raif::Utils::Colors.red("  #{e.backtrace.join("\n  ")}")
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

          raise ActiveRecord::Rollback
        end

        @current_eval
      end

      def file(filename)
        # Validate filename to prevent directory traversal
        raise ArgumentError, "Invalid filename: cannot be empty" if filename.nil? || filename.empty?
        raise ArgumentError, "Invalid filename: cannot contain '..' or absolute paths" if filename.include?("..") || filename.start_with?("/")

        # Ensure we're only accessing files within the raif_evals/files directory
        base_path = Rails.root.join("raif_evals", "files")
        full_path = base_path.join(filename)

        # Verify the resolved path is within the expected directory
        unless full_path.to_s.start_with?(base_path.to_s)
          raise ArgumentError, "Invalid filename: path traversal detected"
        end

        if full_path.exist?
          full_path.read
        else
          raise ArgumentError, "File #{filename} does not exist in raif_evals/files/"
        end
      end

    end
  end
end
