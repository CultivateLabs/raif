# frozen_string_literal: true

class Raif::TestUser < ApplicationRecord
  has_one_attached :avatar
  has_many_attached :documents

  def preferred_language_key
    # no-op so we can stub in tests
  end
end
