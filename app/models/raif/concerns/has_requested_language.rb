# frozen_string_literal: true

module Raif::Concerns::HasRequestedLanguage
  extend ActiveSupport::Concern

  included do
    validates :requested_language_key, inclusion: { in: Raif.supported_languages, allow_blank: true }
  end

  def requested_language_name
    @requested_language_name ||= I18n.t("raif.languages.#{requested_language_key}", locale: "en")
  end

  def system_prompt_language_preference
    return if requested_language_key.blank?

    "You're collaborating with teammate who speaks #{requested_language_name}. Please respond in #{requested_language_name}."
  end

end
