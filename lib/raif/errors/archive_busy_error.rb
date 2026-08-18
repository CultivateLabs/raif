# frozen_string_literal: true

module Raif
  module Errors
    # Raised by Raif::Archive.purge_partition! when the shared archive
    # advisory lock is held (an archive job run or another purge is in
    # progress). Retryable: nothing was deleted; retry once the concurrent
    # operation finishes.
    class ArchiveBusyError < StandardError
    end
  end
end
