# frozen_string_literal: true

module Raif
  module Evals
    # Collects the Raif::ModelCompletion records created while one eval's block runs, so the
    # eval's result reports exactly the LLM calls that eval caused.
    #
    # Holds the same objects Raif::Llm mutates in place as a request progresses, so tokens and
    # cost are read off the live records rather than re-queried out of a transaction that is
    # about to be rolled back.
    #
    # Scoped per thread (per fiber under isolation_level: :fiber), so concurrent evals stay
    # correct. The trade is that a completion created on another thread mid-eval is not captured.
    module ModelCompletionSink
      STATE_KEY = :raif_evals_model_completion_sink

      class << self
        # Starts collecting and returns the array completions will be pushed onto. The caller
        # holds that array, so it can read what was collected after #close.
        def open
          ActiveSupport::IsolatedExecutionState[STATE_KEY] = []
        end

        def close
          ActiveSupport::IsolatedExecutionState.delete(STATE_KEY)
        end

        # Called from the create.raif_model_completion subscriber in raif/evals.rb, so it sees
        # every completion however it was created, including ones a host app's own code or a
        # factory creates. A no-op unless an eval has opened a sink on this thread.
        def record(model_completion)
          ActiveSupport::IsolatedExecutionState[STATE_KEY]&.push(model_completion)
        end
      end
    end
  end
end
