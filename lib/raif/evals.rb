# frozen_string_literal: true

require "raif/evals/model_completion_sink"
require "raif/evals/statistics"
require "raif/evals/console_line"
require "raif/evals/console_writer"
require "raif/evals/worker_pool"
require "raif/evals/expectation_result"
require "raif/evals/score_result"
require "raif/evals/eval_case"
require "raif/evals/eval_definition"
require "raif/evals/execution"
require "raif/evals/dataset"
require "raif/evals/eval_result"
require "raif/evals/eval_set"
require "raif/evals/eval_set_coordinator"
require "raif/evals/comparison"
require "raif/evals/comparison_report"
require "raif/evals/run_log"
require "raif/evals/run"

module Raif
  module Evals
    # Namespace modules for organizing eval sets
    module Tasks
    end

    module Conversations
    end

    module Agents
    end
  end
end

# Subscribed on load rather than per run: requiring this file is what makes an eval run possible,
# and the sink is inert until an eval opens it. The subscription is global while collection is
# per-thread, so concurrent evals keep their own completions.
#
# The block closes over the sink instead of naming it: app/models/raif/evals makes Raif::Evals a
# Zeitwerk-managed namespace, so a reload would drop the constant this file requires and resolving
# one per event would raise on a host app's own LLM calls.
sink = Raif::Evals::ModelCompletionSink
ActiveSupport::Notifications.subscribe("create.raif_model_completion") do |event|
  sink.record(event.payload[:model_completion])
end
