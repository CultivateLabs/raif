# frozen_string_literal: true

module Raif
  module Evals
    module EvalSets
      module Expectations

        def expect(description, result_metadata: nil, &block)
          result = begin
            if block.call
              output.puts Raif::Utils::Colors.green("  ✓ #{description}")
              output.puts Raif::Utils::Colors.green("    ⎿ #{result_metadata.inspect}") if result_metadata && Raif.config.evals_verbose_output
              ExpectationResult.new(description: description, status: :passed, metadata: result_metadata)
            else
              output.puts Raif::Utils::Colors.red("  ✗ #{description}")
              output.puts Raif::Utils::Colors.red("    ⎿ #{result_metadata.inspect}") if result_metadata && Raif.config.evals_verbose_output
              ExpectationResult.new(description: description, status: :failed, metadata: result_metadata)
            end
          rescue => e
            output.puts Raif::Utils::Colors.red("  ✗ #{description} (Error: #{e.message})")
            ExpectationResult.new(description: description, status: :error, error: e, metadata: result_metadata)
          end

          current_eval_result.add_expectation_result(result)
          result
        end

        # Records a number on the eval result. Pass/fail expectations alone have a ceiling:
        # once two models clear every bar their results are identical, and any quality
        # difference short of missing a bar is invisible.
        #
        # Passing min: and/or max: also gates the eval on the value, so a score can replace
        # an expect block rather than sitting alongside one.
        def score(name, value, scale: nil, min: nil, max: nil, higher_is_better: true)
          score_result = ScoreResult.new(
            name: name,
            value: value,
            scale: scale,
            min: min,
            max: max,
            higher_is_better: higher_is_better
          )
          current_eval_result.add_score(score_result)

          output.puts "    #{score_result.name}: #{score_result.formatted_value}"
          expect(score_result.gate_description) { score_result.passed? } if score_result.gated?

          score_result
        end

        def expect_tool_invocation(tool_invoker, tool_type, with: {})
          invocations = tool_invoker.raif_model_tool_invocations.select { |inv| inv.tool_type == tool_type }
          invoked_tools = tool_invoker.raif_model_tool_invocations.map{|inv| [inv.tool_type, inv.tool_arguments] }.to_h

          if with.any?
            invocations = invocations.select do |invocation|
              with.all? { |key, value| invocation.tool_arguments[key.to_s] == value }
            end
          end

          result_metadata = { invoked_tools: invoked_tools }
          expect "invokes #{tool_type}#{with.any? ? " with #{with.to_json}" : ""}", result_metadata: result_metadata do
            invocations.any?
          end
        end

        def expect_no_tool_invocation(tool_invoker, tool_name)
          expect "does not invoke #{tool_name}" do
            tool_invoker.raif_model_tool_invocations.none? { |inv| inv.tool_name == tool_name }
          end
        end

      end
    end
  end
end
