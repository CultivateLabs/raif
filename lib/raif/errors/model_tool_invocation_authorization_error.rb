# frozen_string_literal: true

module Raif
  module Errors
    # Marker module mixed into any exception raised by a
    # Raif.config.model_tool_invocation_authorizer. The original exception class
    # and message raised by the host app are preserved.
    #
    # An agent treats a veto as an error the model cannot work around, so it
    # fails the run instead of sending the model an error result. A conversation
    # entry fails, as it does for any tool exception. Raif::ModelTool.invoke_tool
    # re-raises it to the caller.
    module ModelToolInvocationAuthorizationError
    end
  end
end
