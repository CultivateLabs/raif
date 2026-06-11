# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::StreamingResponses::OpenAiResponses, type: :model do
  subject(:streaming_response) { described_class.new }

  let(:llm) { Raif.llm(:open_ai_responses_gpt_4o) }

  before do
    allow(Raif.config).to receive(:llm_api_requests_enabled).and_return(true)
  end

  def model_completion
    @model_completion ||= Raif::ModelCompletion.new(
      llm_model_key: "open_ai_responses_gpt_4o",
      model_api_name: "gpt-4o"
    )
  end

  it "surfaces an incomplete (max_output_tokens) stream so it is flagged as truncated" do
    streaming_response.process_streaming_event("response.created", { "type" => "response.created", "response" => { "id" => "resp_1" } })
    streaming_response.process_streaming_event("response.incomplete", {
      "type" => "response.incomplete",
      "response" => {
        "id" => "resp_1",
        "status" => "incomplete",
        "incomplete_details" => { "reason" => "max_output_tokens" },
        "usage" => { "input_tokens" => 100, "output_tokens" => 32_768, "total_tokens" => 32_868 }
      }
    })

    json = streaming_response.current_response_json
    expect(json["status"]).to eq("incomplete")
    expect(json.dig("incomplete_details", "reason")).to eq("max_output_tokens")

    llm.send(:update_model_completion, model_completion, json)
    expect(model_completion.response_finish_reason).to eq("max_output_tokens")
    expect(model_completion).to be_truncated
  end

  it "surfaces a completed stream without flagging it as truncated" do
    streaming_response.process_streaming_event("response.created", { "type" => "response.created", "response" => { "id" => "resp_1" } })
    streaming_response.process_streaming_event("response.completed", {
      "type" => "response.completed",
      "response" => {
        "id" => "resp_1",
        "status" => "completed",
        "usage" => { "input_tokens" => 10, "output_tokens" => 5, "total_tokens" => 15 }
      }
    })

    json = streaming_response.current_response_json
    expect(json["status"]).to eq("completed")

    llm.send(:update_model_completion, model_completion, json)
    expect(model_completion.response_finish_reason).to eq("completed")
    expect(model_completion).not_to be_truncated
  end
end
