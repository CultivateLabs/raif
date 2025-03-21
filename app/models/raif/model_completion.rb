# frozen_string_literal: true

class Raif::ModelCompletion < Raif::ApplicationRecord
  include Raif::Concerns::LlmResponseParsing

  belongs_to :source, polymorphic: true, optional: true

  validates :llm_model_key, presence: true, inclusion: { in: ->{ Raif.available_llm_keys.map(&:to_s) } }
  validates :model_api_name, presence: true
  validates :type, presence: true

  after_initialize -> { self.messages ||= [] }

  # Triggers the call to the LLM to get the response. Must be implemented by llm provider-specific subclasses.
  def prompt_model_for_response!
    raise NotImplementedError, "Raif::ModelCompletion subclasses must implement #prompt_model_for_response!"
  end

protected

  def default_temperature
    0.7
  end

private

  def default_json_response_schema
    {
      type: "object",
      properties: {
        response: {
          type: "string",
          description: "The complete response text"
        }
      },
      required: ["response"],
      additionalProperties: false,
      description: "Return a single text response containing your complete answer"
    }
  end
end
