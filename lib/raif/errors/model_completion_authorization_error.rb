# frozen_string_literal: true

module Raif
  module Errors
    # Marker module mixed into any exception raised by a
    # Raif.config.model_completion_authorizer. Synchronous entry points that
    # rescue StandardError (Raif::Task.run) check for it so they can re-raise an
    # intentional authorization veto to the caller instead of swallowing it and
    # reporting it as an ordinary model failure. The original exception class
    # and message raised by the host app are preserved.
    #
    # The conversation flow runs inside Raif::ConversationEntryJob (the top of
    # the stack, with no host caller to receive a raise), so a veto there simply
    # surfaces as a failed Raif::ConversationEntry rather than propagating.
    module ModelCompletionAuthorizationError
    end
  end
end
