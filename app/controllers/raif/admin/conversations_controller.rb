# frozen_string_literal: true

module Raif
  module Admin
    class ConversationsController < Raif::Admin::ApplicationController
      def index
        @pagy, @conversations = pagy(Raif::Conversation.order(created_at: :desc))
      end

      def show
        @conversation = Raif::Conversation.find(params[:id])
      end
    end
  end
end
