# frozen_string_literal: true

module Raif
  module Agents
    class ReActStep
      attr_reader :model_response_text

      def initialize(model_response_text:)
        @model_response_text = model_response_text
      end

      def thought
        @thought ||= extract_tag_content("thought")
      end

      def answer
        @answer ||= extract_tag_content("answer")
      end

      def action
        @action ||= extract_tag_content("action")
      end

    private

      def extract_tag_content(tag_name)
        match = model_response_text.match(%r{<#{tag_name}>(.*?)</#{tag_name}>}m)
        match && match[1] ? match[1].strip : nil
      end
    end
  end
end
