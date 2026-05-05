# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_test_users
#
#  id         :bigint           not null, primary key
#  email      :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class Raif::TestUser < ApplicationRecord
  has_one_attached :avatar
  has_many_attached :documents

  def preferred_language_key
    # no-op so we can stub in tests
  end
end
