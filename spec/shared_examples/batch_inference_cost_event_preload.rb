# frozen_string_literal: true

# Requires an "ended" `batch`, a `creator`, and `stub_successful_batch_results`,
# a lambda that stubs the provider so every given custom id comes back as a
# successful entry.
RSpec.shared_examples "a batch provider that preloads inference cost events" do
  it "loads the batch's inference cost events in one query when finalize! fetches results" do
    tasks = Array.new(5) do |i|
      Raif::TestTask.build_for_batch(
        batch: batch,
        batch_custom_id: "preload-#{i}",
        creator: creator,
        llm_model_key: batch.llm_model_key
      )
    end
    custom_ids = batch.raif_model_completions.pluck(:batch_custom_id)
    stub_successful_batch_results.call(custom_ids)

    cost_event_selects = []
    callback = ->(*_args, payload) do
      next if payload[:name] == "SCHEMA"

      sql = payload[:sql].to_s
      cost_event_selects << sql if sql.start_with?("SELECT") && sql.include?('FROM "raif_inference_cost_events"')
    end

    # finalize! is the poll job's path. It fetches inside with_lock, so each
    # completion's cost event sync runs only after the whole fetch commits.
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      batch.finalize!
    end

    expect(tasks.map { |t| t.raif_model_completion.reload }).to all(be_completed)
    expect(Raif::InferenceCostEvent.where(raif_model_completion_batch_id: batch.id).count).to eq(custom_ids.size)
    expect(cost_event_selects.size).to eq(1)
  end
end
