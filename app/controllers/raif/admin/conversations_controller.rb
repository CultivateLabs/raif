# frozen_string_literal: true

module Raif
  module Admin
    class ConversationsController < Raif::Admin::ApplicationController
      def index
        @pagy, @conversations = pagy(Raif::Conversation.order(Arel.sql("latest_entry_at IS NULL, latest_entry_at DESC, created_at DESC")))
      end

      def show
        @conversation = Raif::Conversation.find(params[:id])

        # Archived cost events for all of this conversation's entries, loaded
        # once with their archives and grouped by entry id: the entry partial
        # renders archived-attempt badges from this hash instead of querying
        # per rendered entry. Stamp-only: an event without raif_archive_id
        # belongs to a completion deleted outside the archive job, which was
        # never archived, so nothing may claim it was.
        @archived_events_by_entry_id = Raif::InferenceCostEvent
          .where(source: @conversation.entries, raif_model_completion_id: nil)
          .where.not(raif_archive_id: nil)
          .includes(:raif_archive)
          .order(:id)
          .group_by(&:source_id)
      end
    end
  end
end
