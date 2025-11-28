# frozen_string_literal: true

module Raif
  module Admin
    TaskStat = Data.define(:type, :llm_model_key, :count, :input_cost, :output_cost, :total_cost)
  end
end
