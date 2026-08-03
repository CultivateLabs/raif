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
          evals << { description: description, block: block, definition_line_number: caller_locations(1, 1).first.lineno }
        end

        def setup(&block)
          @setup_block = block
        end

        def teardown(&block)
          @teardown_block = block
        end

        def run(output: $stdout, repeats: 1)
          new(output: output).run(repeats: repeats)
        end
      end

      # Each repeat re-runs setup and the eval block from scratch, so the repeats are
      # independent samples of a non-deterministic model rather than a re-scoring of one
      # response. Comparing models needs the pass rate across them, not a single draw.
      def run(repeats: 1)
        @results = []

        self.class.evals.each_with_index do |eval_definition, eval_index|
          repeats.times do |i|
            @results << run_eval(eval_definition, run_index: (i + 1 if repeats > 1), eval_index: eval_index)
          end
        end

        @results
      end

      def run_eval(eval_definition, run_index: nil, eval_index: nil)
        @current_eval = Eval.new(
          description: eval_definition[:description],
          run_index: run_index,
          eval_index: eval_index || self.class.evals.index(eval_definition)
        )

        output.puts "Running: #{eval_definition[:description]}#{" (run #{run_index})" if run_index}"

        ActiveRecord::Base.transaction do
          instance_eval(&self.class.setup_block) if self.class.setup_block

          # Baseline id captured after setup so we only record the LLM calls the eval
          # itself makes. Model completions are persisted during the eval but rolled back
          # below, so they must be captured before the rollback.
          model_completions_start_id = Raif::ModelCompletion.maximum(:id) || 0

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
            # Capture completions before teardown: sources like Raif::Agent and
            # Raif::ConversationEntry declare `has_many :raif_model_completions,
            # dependent: :destroy`, so a teardown that destroys them would delete the
            # rows we need before we can read them.
            capture_model_completions(model_completions_start_id)

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

    private

      # Records the model completions created during the eval (those with an id greater
      # than the baseline captured before the eval ran) onto the current eval so they can
      # be exported. Wrapped defensively so a capture failure never fails the eval itself.
      def capture_model_completions(start_id)
        completions = Raif::ModelCompletion.where("id > ?", start_id).order(:id).to_a
        @current_eval.record_model_completions(completions)
      rescue => e
        output.puts Raif::Utils::Colors.red("  Error capturing model completions: #{e.message}")
      end

    end
  end
end
