# frozen_string_literal: true

class Raif::TestAdapter < Raif::ApiAdapters::Base
  attr_accessor :chat_handler

  def chat(messages:, response_format: :text, system_prompt: nil)
    Raif::ModelResponse.new(
      raw_response: chat_handler.call(messages),
      response_format: response_format,
      prompt_tokens: rand(1..4),
      completion_tokens: rand(10..30),
      total_tokens: rand(14..34)
    )
  end
end
