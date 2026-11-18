# frozen_string_literal: true

module Raif
  class ApplicationJob < ::ApplicationJob
    include ActionView::RecordIdentifier

    # Runs the block once every open database transaction has committed, or
    # right away when there is none. A job queued from inside a transaction
    # (for example host code that calls `invocation.complete!` in one) can start
    # before the commit and would not see the rows it was queued for.
    def self.after_transaction_commit(&block)
      if ActiveRecord.respond_to?(:after_all_transactions_commit)
        ActiveRecord.after_all_transactions_commit(&block)
      else
        yield
      end
    end

  end
end
