# frozen_string_literal: true

module Raif
  module Evals
    # One execution's worth of work: one eval block, against one case, on one repeat. Every
    # execution in the run is listed before any of them runs, so there is a flat work list to hand
    # a pool of threads rather than a nested loop that can only be walked in order.
    #
    # case_id_width is presentation, not work - the widest case id among the eval's selected
    # cases, so the compact console lines align. It travels with the execution because the
    # instance that runs it never resolved the datasets it would be measured from.
    Execution = Struct.new(:eval_definition, :eval_case, :run_index, :case_id_width, keyword_init: true) do
      def eval_id
        eval_definition.id
      end

      def eval_index
        eval_definition.index
      end
    end
  end
end
