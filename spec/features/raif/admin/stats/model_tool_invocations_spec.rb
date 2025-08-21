# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Stats::ModelToolInvocations", type: :feature do
  let(:creator) { FB.create(:raif_test_user) }
  let(:task) { FB.create(:raif_test_task, creator: creator) }
  let(:conversation) { FB.create(:raif_conversation, creator: creator) }
  let(:conversation_entry) { FB.create(:raif_conversation_entry, raif_conversation: conversation) }

  describe "index page" do
    # Create model tool invocations of different types
    let!(:wiki_invocation1) do
      FB.create(
        :raif_model_tool_invocation,
        source: task,
        tool_type: "Raif::ModelTools::WikipediaSearch",
        tool_arguments: { "query" => "Ruby programming" },
        created_at: 12.hours.ago
      )
    end

    let!(:wiki_invocation2) do
      FB.create(
        :raif_model_tool_invocation,
        source: conversation_entry,
        tool_type: "Raif::ModelTools::WikipediaSearch",
        tool_arguments: { "query" => "Rails framework" },
        created_at: 12.hours.ago
      )
    end

    let!(:fetch_invocation) do
      FB.create(
        :raif_model_tool_invocation,
        source: task,
        tool_type: "Raif::ModelTools::FetchUrl",
        tool_arguments: { "url" => "https://example.com" },
        created_at: 12.hours.ago
      )
    end

    let!(:test_tool_invocation) do
      FB.create(
        :raif_model_tool_invocation,
        source: conversation_entry,
        tool_type: "Raif::TestModelTool",
        tool_arguments: { "items" => [{ "title" => "foo", "description" => "bar" }] },
        created_at: 12.hours.ago
      )
    end

    # Create older invocation of a different type
    let!(:old_invocation) do
      FB.create(
        :raif_model_tool_invocation,
        source: task,
        tool_type: "Raif::ModelTools::FetchUrl",
        tool_arguments: { "url" => "https://old-example.com" },
        created_at: 2.days.ago
      )
    end

    it "displays model tool invocation stats by type with counts for different periods" do
      visit raif.admin_stats_model_tool_invocations_path

      # Check page title and back link
      expect(page).to have_content(I18n.t("raif.admin.stats.model_tool_invocations.title"))
      expect(page).to have_link(I18n.t("raif.admin.stats.model_tool_invocations.back_to_stats"), href: raif.admin_stats_path)

      # Check period filter has day selected by default
      expect(page).to have_select("period", selected: I18n.t("raif.admin.common.period_day"))

      # Check table headers
      within("table thead") do
        expect(page).to have_content(I18n.t("raif.admin.common.tool_type"))
        expect(page).to have_content(I18n.t("raif.admin.common.count"))
      end

      # For day period, we should only see invocations from the last 24 hours
      within("table tbody") do
        # Check WikipediaSearch invocations (should have 2)
        wiki_row = page.find("td", text: "Raif::ModelTools::WikipediaSearch").ancestor("tr")
        expect(wiki_row.find("td:last-child")).to have_content("2")

        # Check FetchUrl invocations (should have 1 in last 24 hours)
        fetch_row = page.find("td", text: "Raif::ModelTools::FetchUrl").ancestor("tr")
        expect(fetch_row.find("td:last-child")).to have_content("1")

        # Check TestModelTool invocations (should have 1)
        test_row = page.find("td", text: "Raif::TestModelTool").ancestor("tr")
        expect(test_row.find("td:last-child")).to have_content("1")
      end

      # Change period to "all"
      select I18n.t("raif.admin.common.period_all"), from: "period"
      click_button I18n.t("raif.admin.common.update")

      # Now we should see all invocations including the older one
      within("table tbody") do
        # FetchUrl should now have 2 invocations (1 recent + 1 old)
        fetch_row = page.find("td", text: "Raif::ModelTools::FetchUrl").ancestor("tr")
        expect(fetch_row.find("td:last-child")).to have_content("2")

        # WikipediaSearch should still have 2 (no old ones)
        wiki_row = page.find("td", text: "Raif::ModelTools::WikipediaSearch").ancestor("tr")
        expect(wiki_row.find("td:last-child")).to have_content("2")
      end
    end

    it "handles different period filters correctly" do
      visit raif.admin_stats_model_tool_invocations_path

      # Test week period
      select I18n.t("raif.admin.common.period_week"), from: "period"
      click_button I18n.t("raif.admin.common.update")

      expect(page).to have_select("period", selected: I18n.t("raif.admin.common.period_week"))
      within("table tbody") do
        # Should see recent invocations but not the 2-day-old one
        expect(page).to have_content("Raif::ModelTools::WikipediaSearch")
        expect(page).to have_content("Raif::TestModelTool")
      end

      # Test month period
      select I18n.t("raif.admin.common.period_month"), from: "period"
      click_button I18n.t("raif.admin.common.update")

      expect(page).to have_select("period", selected: I18n.t("raif.admin.common.period_month"))
      within("table tbody") do
        # Should see all invocations including the old one
        fetch_row = page.find("td", text: "Raif::ModelTools::FetchUrl").ancestor("tr")
        expect(fetch_row.find("td:last-child")).to have_content("2")
      end
    end

    it "displays correct counts when no data exists" do
      # Remove all invocations
      Raif::ModelToolInvocation.destroy_all

      visit raif.admin_stats_model_tool_invocations_path

      # Should show empty table
      within("table tbody") do
        expect(page).not_to have_content("Raif::ModelTools::WikipediaSearch")
        expect(page).not_to have_content("Raif::ModelTools::FetchUrl")
        expect(page).not_to have_content("Raif::TestModelTool")
      end
    end
  end
end
