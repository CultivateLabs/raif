# frozen_string_literal: true

module Raif
  module Errors
    # Not in the default llm_request_retriable_exceptions: a refusal is a verdict on the prompt,
    # so resending the same prompt pays for the same refusal again.
    class RefusalError < StandardError
    end
  end
end
