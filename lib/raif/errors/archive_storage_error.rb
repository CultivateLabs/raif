# frozen_string_literal: true

module Raif
  module Errors
    # Raised when an archive storage adapter violates the write contract
    # (returns a blank location, or the written object fails verification).
    # The archive job treats this like any upload failure: the run aborts and
    # zero rows are recorded or deleted.
    class ArchiveStorageError < StandardError
    end
  end
end
