# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::ModelCompletionBatches", type: :feature do
  let(:user) { FB.create(:raif_test_user) }

  describe "index page" do
    let!(:pending_batch) do
      FB.create(
        :raif_model_completion_batch_anthropic,
        status: "pending",
        creator: user
      )
    end

    let!(:in_progress_batch) do
      FB.create(
        :raif_model_completion_batch_open_ai_responses,
        status: "in_progress",
        provider_batch_id: "batch_in_progress_123",
        submitted_at: 1.hour.ago,
        started_at: 30.minutes.ago,
        creator: user
      )
    end

    let!(:ended_batch) do
      FB.create(
        :raif_model_completion_batch_open_ai_responses,
        status: "ended",
        provider_batch_id: "batch_ended_456",
        submitted_at: 2.hours.ago,
        started_at: 90.minutes.ago,
        ended_at: 30.minutes.ago,
        total_cost: 0.123456,
        creator: user
      )
    end

    let!(:failed_batch) do
      FB.create(
        :raif_model_completion_batch_google,
        status: "failed",
        provider_batch_id: "batch_failed_789",
        failed_at: 10.minutes.ago,
        failure_reason: "Provider returned 500",
        creator: user
      )
    end

    it "lists all batches with key columns" do
      visit raif.admin_model_completion_batches_path

      expect(page).to have_content(I18n.t("raif.admin.common.model_completion_batches"))
      expect(page).to have_css("tr.raif-model-completion-batch", count: 4)

      expect(page).to have_content("Raif::ModelCompletionBatches::Anthropic")
      expect(page).to have_content("Raif::ModelCompletionBatches::OpenAi")
      expect(page).to have_content("Raif::ModelCompletionBatches::Google")

      expect(page).to have_content("batch_in_progress_123")
      expect(page).to have_content("batch_ended_456")
      expect(page).to have_content("batch_failed_789")

      expect(page).to have_content("$0.123456")

      expect(page).to have_link("##{ended_batch.id}", href: raif.admin_model_completion_batch_path(ended_batch))
    end

    it "filters by status" do
      visit raif.admin_model_completion_batches_path
      expect(page).to have_css("tr.raif-model-completion-batch", count: 4)

      select "Ended", from: "status"
      click_button I18n.t("raif.admin.common.filter")

      expect(page).to have_css("tr.raif-model-completion-batch", count: 1)
      expect(page).to have_content("batch_ended_456")
    end

    it "filters by type" do
      visit raif.admin_model_completion_batches_path

      select "Raif::ModelCompletionBatches::Anthropic", from: "type"
      click_button I18n.t("raif.admin.common.filter")

      expect(page).to have_css("tr.raif-model-completion-batch", count: 1)
      expect(page).to have_content("Raif::ModelCompletionBatches::Anthropic")
    end

    it "shows the empty state when there are no batches" do
      Raif::ModelCompletionBatch.delete_all
      visit raif.admin_model_completion_batches_path
      expect(page).to have_content(I18n.t("raif.admin.common.no_model_completion_batches"))
    end
  end

  describe "show page" do
    let(:batch) do
      FB.create(
        :raif_model_completion_batch_anthropic,
        status: "ended",
        provider_batch_id: "batch_show_123",
        submitted_at: 2.hours.ago,
        started_at: 90.minutes.ago,
        ended_at: 30.minutes.ago,
        total_cost: 0.5,
        prompt_token_cost: 0.3,
        output_token_cost: 0.2,
        completion_handler_class_name: "SomeHandler",
        request_counts: { "completed" => 2, "failed" => 0 },
        metadata: { "source" => "test" },
        provider_response: { "results_url" => "https://example.com/results" },
        creator: user
      )
    end

    let!(:completion_one) do
      Raif::ModelCompletion.create!(
        raif_model_completion_batch: batch,
        batch_custom_id: "item_1",
        llm_model_key: "anthropic_claude_4_5_haiku",
        model_api_name: "claude-haiku-4-5",
        response_format: "text",
        raw_response: "First batch result",
        prompt_tokens: 100,
        completion_tokens: 50,
        total_tokens: 150,
        total_cost: 0.01,
        completed_at: 1.hour.ago,
        started_at: 90.minutes.ago
      )
    end

    let!(:completion_two) do
      Raif::ModelCompletion.create!(
        raif_model_completion_batch: batch,
        batch_custom_id: "item_2",
        llm_model_key: "anthropic_claude_4_5_haiku",
        model_api_name: "claude-haiku-4-5",
        response_format: "text",
        raw_response: "Second batch result",
        prompt_tokens: 80,
        completion_tokens: 40,
        total_tokens: 120,
        total_cost: 0.008,
        completed_at: 1.hour.ago,
        started_at: 90.minutes.ago
      )
    end

    it "displays batch details and its child completions" do
      visit raif.admin_model_completion_batch_path(batch)

      expect(page).to have_content(I18n.t("raif.admin.model_completion_batches.show.title", id: batch.id))

      expect(page).to have_content("Raif::ModelCompletionBatches::Anthropic")
      expect(page).to have_content("anthropic_claude_4_5_haiku")
      expect(page).to have_content("claude-haiku-4-5")
      expect(page).to have_content("batch_show_123")
      expect(page).to have_content("SomeHandler")

      expect(page).to have_content("$0.500000")
      expect(page).to have_content("$0.300000")
      expect(page).to have_content("$0.200000")

      expect(page).to have_content(I18n.t("raif.admin.common.request_counts"))
      expect(page).to have_content('"completed": 2')

      expect(page).to have_content(I18n.t("raif.admin.common.metadata"))
      expect(page).to have_content('"source": "test"')

      expect(page).to have_content(I18n.t("raif.admin.common.provider_response"))
      expect(page).to have_content("https://example.com/results")

      expect(page).to have_link("##{completion_one.id}", href: raif.admin_model_completion_path(completion_one))
      expect(page).to have_link("##{completion_two.id}", href: raif.admin_model_completion_path(completion_two))
      expect(page).to have_content("item_1")
      expect(page).to have_content("item_2")
      expect(page).to have_content("First batch result")
      expect(page).to have_content("Second batch result")

      click_link I18n.t("raif.admin.model_completion_batches.show.back_to_model_completion_batches")
      expect(page).to have_current_path(raif.admin_model_completion_batches_path)
    end

    it "shows failure details when present" do
      failed_batch = FB.create(
        :raif_model_completion_batch_anthropic,
        status: "failed",
        failed_at: 5.minutes.ago,
        failure_error: "ProviderError",
        failure_reason: "Something went wrong"
      )

      visit raif.admin_model_completion_batch_path(failed_batch)

      expect(page).to have_content("ProviderError")
      expect(page).to have_content("Something went wrong")
    end

    it "shows no_model_completions when batch has no children" do
      empty_batch = FB.create(:raif_model_completion_batch_anthropic)
      visit raif.admin_model_completion_batch_path(empty_batch)
      expect(page).to have_content(I18n.t("raif.admin.common.no_model_completions"))
    end

    it "links to the batch from the model_completion show page" do
      visit raif.admin_model_completion_path(completion_one)
      expect(page).to have_link("##{batch.id}", href: raif.admin_model_completion_batch_path(batch))
    end
  end
end
