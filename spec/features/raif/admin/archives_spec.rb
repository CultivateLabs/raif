# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Archives", type: :feature do
  let(:creator) { FB.create(:raif_test_user) }

  def cull_completion!(completion, archive)
    Raif::InferenceCostEvent
      .where(raif_model_completion_id: completion.id)
      .update_all(raif_archive_id: archive.id)
    Raif::ModelCompletion.where(id: completion.id).delete_all
  end

  describe "index page" do
    it "lists archives with resource type, id range, count, and key" do
      archive = FB.create(:raif_archive, first_record_id: 10, last_record_id: 500, record_count: 42)

      visit raif.admin_archives_path

      expect(page).to have_content(I18n.t("raif.admin.common.archives"))
      expect(page).to have_content("Raif::ModelCompletion")
      expect(page).to have_content("10-500")
      expect(page).to have_content("42")
      expect(page).to have_content(archive.cutoff_at.to_date.to_s)
      # The key displays truncated; the full value rides the copy-to-clipboard attribute.
      expect(page).to have_css("[data-raif-copy-text='#{archive.key}']")
    end

    it "shows an empty state when no archives exist" do
      visit raif.admin_archives_path

      expect(page).to have_content(I18n.t("raif.admin.common.no_archives"))
    end
  end

  describe "show page" do
    it "renders the full audit row and states that payloads are not browsable" do
      archive = FB.create(:raif_archive, record_count: 7, compressed_bytes: 2048, checksum_sha256: "abc123def456")

      visit raif.admin_archive_path(archive)

      expect(page).to have_content(I18n.t("raif.admin.archives.show.title", id: archive.id))
      expect(page).to have_content(I18n.t("raif.admin.archives.show.not_browsable_notice"))
      expect(page).to have_content(archive.key)
      expect(page).to have_content("abc123def456")
      expect(page).to have_content("7")
      expect(page).to have_content("2 KB")
      expect(page).to have_content(I18n.t("raif.admin.archives.show.working_with_title"))
      expect(page).to have_content(I18n.t("raif.admin.archives.show.working_with_format"))
      expect(page).to have_content("shasum -a 256")
    end
  end

  describe "retention banner on the model completions index" do
    it "appears when archiving and a retention period are configured" do
      allow(Raif.config).to receive_messages(
        archive_enabled: true,
        model_completion_retention_period: 6.months
      )

      visit raif.admin_model_completions_path

      expect(page).to have_content(I18n.t("raif.admin.model_completions.index.retention_banner", period: "6 months"))
      expect(page).to have_link(I18n.t("raif.admin.model_completions.index.see_archives"), href: raif.admin_archives_path)
    end

    it "does not appear when archiving is disabled" do
      visit raif.admin_model_completions_path

      expect(page).not_to have_content(I18n.t("raif.admin.model_completions.index.see_archives"))
    end
  end

  describe "retention footnote on the stats page" do
    it "appears when archiving and a retention period are configured" do
      allow(Raif.config).to receive_messages(
        archive_enabled: true,
        model_completion_retention_period: 6.months
      )

      visit raif.admin_stats_path

      expect(page).to have_content(I18n.t("raif.admin.stats.index.retention_footnote", period: "6 months"))
    end

    it "does not appear when archiving is disabled" do
      visit raif.admin_stats_path

      expect(page).not_to have_content("retention window")
    end
  end

  describe "config page" do
    it "surfaces the archive settings" do
      allow(Raif.config).to receive_messages(
        archive_enabled: true,
        archive_storage: Raif::ArchiveStorage::FileSystem.new(root: Dir.mktmpdir),
        model_completion_retention_period: 6.months
      )

      visit raif.admin_config_path

      expect(page).to have_content("archive_enabled")
      expect(page).to have_content("archive_storage")
      expect(page).to have_content("Raif::ArchiveStorage::FileSystem")
      expect(page).to have_content("model_completion_retention_period")
      expect(page).to have_content("6 months")
    end
  end

  describe "archived indicators" do
    it "shows durable cost data and an archived badge linking to the archive on a task whose completion was culled" do
      task = FB.create(:raif_test_task, creator: creator)
      completion = FB.create(
        :raif_model_completion,
        llm_model_key: "raif_test_llm",
        model_api_name: "raif-test-llm",
        source: task,
        prompt_tokens: 111,
        completion_tokens: 222,
        total_tokens: 333
      )
      completion.completed!

      archive = FB.create(:raif_archive, first_record_id: completion.id, last_record_id: completion.id, record_count: 1)
      cull_completion!(completion, archive)

      visit raif.admin_task_path(task)

      expect(page).to have_css(".badge", text: I18n.t("raif.admin.common.archived"))
      expect(page).to have_content(I18n.t("raif.admin.common.model_completion_archived_notice"))
      expect(page).to have_content("333")
      expect(page).to have_link("##{archive.id}", href: raif.admin_archive_path(archive))
    end

    it "shows an archived badge linking to the archive on a conversation entry whose completion was culled" do
      conversation = FB.create(:raif_test_conversation, creator: creator)
      entry = FB.create(:raif_conversation_entry, raif_conversation: conversation, creator: creator)
      completion = FB.create(
        :raif_model_completion,
        llm_model_key: "raif_test_llm",
        model_api_name: "raif-test-llm",
        source: entry
      )
      completion.completed!

      archive = FB.create(:raif_archive, first_record_id: completion.id, last_record_id: completion.id, record_count: 1)
      cull_completion!(completion, archive)

      visit raif.admin_conversation_path(conversation)

      expect(page).to have_content(I18n.t("raif.admin.common.archived"))
      expect(page).to have_link(href: raif.admin_archive_path(archive))
    end

    it "renders a conversation's archived attempts with one event query and one archive query" do
      conversation = FB.create(:raif_test_conversation, creator: creator)
      completions = 3.times.map do
        entry = FB.create(:raif_conversation_entry, raif_conversation: conversation, creator: creator)
        completion = FB.create(:raif_model_completion, llm_model_key: "raif_test_llm", model_api_name: "raif-test-llm", source: entry)
        completion.completed!
        completion
      end

      archive = FB.create(
        :raif_archive,
        first_record_id: completions.map(&:id).min,
        last_record_id: completions.map(&:id).max,
        record_count: 3
      )
      completions.each { |completion| cull_completion!(completion, archive) }

      event_queries = []
      archive_queries = []
      callback = ->(*_args, payload) do
        sql = payload[:sql].to_s
        next unless sql.start_with?("SELECT")

        event_queries << sql if sql.include?("raif_inference_cost_events")
        archive_queries << sql if sql.include?("raif_archives")
      end

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        visit raif.admin_conversation_path(conversation)
      end

      expect(page).to have_link(href: raif.admin_archive_path(archive), count: 3)
      expect(event_queries.size).to eq(1)
      expect(archive_queries.size).to eq(1)
    end

    it "never claims a task's completion was archived when its event carries no archive stamp" do
      task = FB.create(:raif_test_task, creator: creator)
      completion = FB.create(
        :raif_model_completion,
        llm_model_key: "raif_test_llm",
        model_api_name: "raif-test-llm",
        source: task
      )
      completion.completed!

      # Deleted outside the archive job (e.g. a source destroy cascade): the
      # event survives with no raif_archive_id, because nothing was archived.
      Raif::ModelCompletion.where(id: completion.id).delete_all

      visit raif.admin_task_path(task)

      expect(page).not_to have_content(I18n.t("raif.admin.common.archived"))
      expect(page).not_to have_content(I18n.t("raif.admin.common.model_completion_archived_notice"))
    end

    it "shows archived attempt badges alongside a retained live attempt on the same conversation entry" do
      conversation = FB.create(:raif_test_conversation, creator: creator)
      entry = FB.create(:raif_conversation_entry, raif_conversation: conversation, creator: creator)
      live = FB.create(:raif_model_completion, llm_model_key: "raif_test_llm", model_api_name: "raif-test-llm", source: entry)
      live.completed!
      culled = FB.create(:raif_model_completion, llm_model_key: "raif_test_llm", model_api_name: "raif-test-llm", source: entry)
      culled.completed!

      archive = FB.create(:raif_archive, first_record_id: culled.id, last_record_id: culled.id, record_count: 1)
      cull_completion!(culled, archive)

      visit raif.admin_conversation_path(conversation)

      expect(page).to have_link(href: raif.admin_model_completion_path(live))
      expect(page).to have_link(href: raif.admin_archive_path(archive))
    end

    it "never claims a conversation entry's completion was archived when its event carries no archive stamp" do
      conversation = FB.create(:raif_test_conversation, creator: creator)
      entry = FB.create(:raif_conversation_entry, raif_conversation: conversation, creator: creator)
      completion = FB.create(
        :raif_model_completion,
        llm_model_key: "raif_test_llm",
        model_api_name: "raif-test-llm",
        source: entry
      )
      completion.completed!

      Raif::ModelCompletion.where(id: completion.id).delete_all

      visit raif.admin_conversation_path(conversation)

      expect(page).not_to have_content(I18n.t("raif.admin.common.archived"))
    end
  end
end
