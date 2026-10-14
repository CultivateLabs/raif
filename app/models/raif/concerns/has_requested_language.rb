# frozen_string_literal: true

module Raif::Concerns::HasRequestedLanguage
  extend ActiveSupport::Concern

  included do
    validate :requested_language_key_supported, if: -> { requested_language_key.present? }
  end

  def requested_language_name
    @requested_language_name ||= Raif.language_name(requested_language_key)
  end

  def system_prompt_language_preference
    return if requested_language_key.blank?

    "\nYou're collaborating with teammate who speaks #{requested_language_name}. Please respond in #{requested_language_name}."
  end

private

  def requested_language_key_supported
    errors.add(:requested_language_key, :inclusion) unless Raif.supported_language_key?(requested_language_key)
  end

end
