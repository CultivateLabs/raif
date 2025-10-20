# frozen_string_literal: true

module Raif::Concerns::AgentInferenceStats
  extend ActiveSupport::Concern

  # Returns the total number of prompt tokens across all model completions
  def total_prompt_tokens
    @total_prompt_tokens ||= raif_model_completions.sum(:prompt_tokens)
  end

  # Returns the total number of completion tokens across all model completions
  def total_completion_tokens
    @total_completion_tokens ||= raif_model_completions.sum(:completion_tokens)
  end

  # Returns the total number of tokens across all model completions
  def total_tokens_sum
    @total_tokens_sum ||= raif_model_completions.sum(:total_tokens)
  end

  # Returns the total cost of prompt tokens across all model completions
  def total_prompt_token_cost
    @total_prompt_token_cost ||= raif_model_completions.sum(:prompt_token_cost)
  end

  # Returns the total cost of output tokens across all model completions
  def total_output_token_cost
    @total_output_token_cost ||= raif_model_completions.sum(:output_token_cost)
  end

  # Returns the total cost across all model completions
  def total_cost
    @total_cost ||= raif_model_completions.sum(:total_cost)
  end
end
