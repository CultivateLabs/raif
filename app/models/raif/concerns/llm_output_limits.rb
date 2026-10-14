# frozen_string_literal: true

# Per-class limits on what a task's model completion may generate. All three
# are opt-in; a class that declares none sends the model's defaults and
# completes a truncated response as before.
#
#   class MyTask < Raif::Task
#     llm_max_completion_tokens 8_000
#     llm_stop_sequences ["END_OF_ANSWER"]
#     llm_fail_on_truncation true
#   end
#
# Stop sequences reach only providers whose API accepts them (Anthropic and
# Google); other providers ignore them. A completion that ends on a stop
# sequence completes normally. With llm_fail_on_truncation, a completion that
# ends at the output cap fails the task instead of completing it with a
# partial response.
module Raif::Concerns::LlmOutputLimits
  extend ActiveSupport::Concern

  included do
    class_attribute :max_completion_tokens, instance_accessor: false, default: nil
    class_attribute :stop_sequences, instance_accessor: false, default: nil
    class_attribute :fail_on_truncation, instance_accessor: false, default: false
  end

  class_methods do
    def llm_max_completion_tokens(max_completion_tokens)
      unless max_completion_tokens.is_a?(Integer) && max_completion_tokens.positive?
        raise ArgumentError, "max_completion_tokens must be a positive integer"
      end

      self.max_completion_tokens = max_completion_tokens
    end

    def llm_stop_sequences(stop_sequences)
      unless Raif::ModelCompletion.valid_stop_sequences?(stop_sequences)
        raise ArgumentError, "stop_sequences must be an array of 1 to #{Raif::ModelCompletion::MAX_STOP_SEQUENCES} non-blank strings"
      end

      self.stop_sequences = stop_sequences.dup.freeze
    end

    def llm_fail_on_truncation(fail_on_truncation)
      raise ArgumentError, "fail_on_truncation must be true or false" unless [true, false].include?(fail_on_truncation)

      self.fail_on_truncation = fail_on_truncation
    end
  end
end
