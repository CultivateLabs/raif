# frozen_string_literal: true

module Raif
  module Admin
    class ArchivesController < Raif::Admin::ApplicationController
      def index
        @pagy, @archives = pagy(Raif::Archive.order(id: :desc))
      end

      def show
        @archive = Raif::Archive.find(params[:id])
      end
    end
  end
end
