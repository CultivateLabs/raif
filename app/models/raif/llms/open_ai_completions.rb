# frozen_string_literal: true

class Raif::Llms::OpenAiCompletions < Raif::Llms::OpenAiBase
  include Raif::Concerns::Llms::OpenAiCompletions::Protocol

  def batch_endpoint_path
    "/v1/chat/completions"
  end

private

  def api_path
    "chat/completions"
  end

  def build_request_parameters(model_completion)
    parameters = {
      model: api_name,
      messages: chat_completions_messages(model_completion, system_prompt: format_system_prompt(model_completion))
    }
    parameters[:temperature] = model_completion.temperature.to_f if supports_temperature?

    apply_chat_completions_tool_parameters!(parameters, model_completion)
    apply_chat_completions_streaming_parameters!(parameters, model_completion)
    apply_chat_completions_response_format!(parameters, model_completion)
  end
end
