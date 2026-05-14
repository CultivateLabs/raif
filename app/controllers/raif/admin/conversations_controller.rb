# frozen_string_literal: true

module Raif
  module Admin
    class ConversationsController < Raif::Admin::ApplicationController
      def index
        @pagy, @conversations = pagy(Raif::Conversation.order(Arel.sql("latest_entry_at IS NULL, latest_entry_at DESC, created_at DESC")))
      end

      def show
        @conversation = Raif::Conversation.find(params[:id])
      end
    end
  end
end
