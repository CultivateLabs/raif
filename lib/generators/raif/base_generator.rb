# frozen_string_literal: true

module Raif
  class BaseGenerator < Rails::Generators::NamedBase
  private

    def raif_module_namespacing(intermediate_modules = [], &block)
      content = capture(&block).rstrip

      modules_names = intermediate_modules + class_path.map(&:camelize)
      modules_names.reverse.each do |module_name|
        content = indent "module #{module_name}\n#{content}\nend", 2
      end

      concat("module Raif\n#{content}\nend\n")
    end

  end
end
