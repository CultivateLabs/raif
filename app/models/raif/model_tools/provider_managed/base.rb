# frozen_string_literal: true

class Raif::ModelTools::ProviderManaged::Base < Raif::ModelTool
  class << self
    def provider_managed?
      true
    end
  end
end
