# frozen_string_literal: true

module Raif
  module Evals
    module EvalSets
      module Expectations

        def expect(description, metadata = {}, &block)
          result = begin
            if block.call
              output.puts Raif::Utils::Colors.green("  ✓ #{description}")
              ExpectationResult.new(description: description, status: :passed, metadata: metadata.presence)
            else
              output.puts Raif::Utils::Colors.red("  ✗ #{description}")
              ExpectationResult.new(description: description, status: :failed, metadata: metadata.presence)
            end
          rescue => e
            output.puts Raif::Utils::Colors.red("  ✗ #{description} (Error: #{e.message})")
            ExpectationResult.new(description: description, status: :error, error: e, metadata: metadata.presence)
          end

          current_eval.add_expectation_result(result)
          result
        end

        def expect_tool_invocation(tool_invoker, tool_name, with: {})
          invocations = tool_invoker.raif_model_tool_invocations.select { |inv| inv.tool_name == tool_name }

          if with.any?
            invocations = invocations.select do |invocation|
              with.all? { |key, value| invocation.tool_arguments[key.to_s] == value }
            end
          end

          expect "invokes #{tool_name}#{with.any? ? " with #{with.inspect}" : ""}" do
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
