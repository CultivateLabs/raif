# frozen_string_literal: true

# A slim, durable record of the cost/token usage of a single model completion.
# Created automatically when a Raif::ModelCompletion reaches a terminal state
# (completed or failed) and retained after the completion row (and, later, its
# source) is deleted, so cost reporting never depends on fat completion rows
# sticking around.
# == Schema Information
#
# Table name: raif_inference_cost_events
#
#  id                             :bigint           not null, primary key
#  cache_creation_input_tokens    :integer
#  cache_read_input_tokens        :integer
#  completion_completed_at        :datetime
#  completion_failed_at           :datetime
#  completion_tokens              :integer
#  incurred_at                    :datetime         not null
#  llm_model_key                  :string           not null
#  metadata                       :jsonb
#  model_api_name                 :string           not null
#  output_token_cost              :decimal(10, 6)
#  prompt_token_cost              :decimal(10, 6)
#  prompt_tokens                  :integer
#  retry_count                    :integer          default(0), not null
#  source_class_name              :string
#  source_type                    :string
#  total_cost                     :decimal(10, 6)
#  total_tokens                   :integer
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  original_model_completion_id   :bigint           not null
#  raif_archive_id                :bigint
#  raif_model_completion_batch_id :bigint
#  raif_model_completion_id       :bigint
#  source_id                      :bigint
#
# Indexes
#
#  index_raif_inference_cost_events_on_incurred_at                (incurred_at)
#  index_raif_inference_cost_events_on_original_completion_id     (original_model_completion_id)
#  index_raif_inference_cost_events_on_raif_archive_id            (raif_archive_id)
#  index_raif_inference_cost_events_on_raif_model_completion_id   (raif_model_completion_id) UNIQUE
#  index_raif_inference_cost_events_on_source_type_and_source_id  (source_type,source_id)
#  index_raif_inference_cost_events_on_source_type_incurred_at    (source_type,incurred_at)
#
# Foreign Keys
#
#  fk_rails_...  (raif_model_completion_id => raif_model_completions.id) ON DELETE => nullify
#
class Raif::InferenceCostEvent < Raif::ApplicationRecord
  belongs_to :raif_model_completion,
    class_name: "Raif::ModelCompletion",
    optional: true,
    inverse_of: :raif_inference_cost_event

  # The source may be culled after the event is created; never validate presence.
  belongs_to :source, polymorphic: true, optional: true

  # Stamped at cull time, immediately before the completion row is deleted,
  # so culled spend links directly to the archive holding its completion.
  # The stamp is authoritative: an event whose completion is gone but that
  # carries no stamp was deleted outside the archive job (e.g. a source
  # destroy cascade) and was never archived.
  belongs_to :raif_archive,
    class_name: "Raif::Archive",
    optional: true,
    inverse_of: :raif_inference_cost_events

  validates :original_model_completion_id, presence: true
  validates :llm_model_key, presence: true
  validates :model_api_name, presence: true
  validates :incurred_at, presence: true

  after_initialize -> { self.metadata ||= {} }

  # Creates events for terminal completions that don't have one yet, and
  # re-syncs events that are STALE (older than their completion: a
  # post-terminal completion update committed but its event re-sync failed).
  # The bulk one-time entry point after upgrading (see the
  # raif:backfill_inference_cost_events rake task);
  # Raif::RepairInferenceCostEventsJob runs the same operation as
  # steady-state self-healing. Terminal-only: pending completions have NULL
  # tokens and contribute nothing to sums, so event sums equal completion
  # sums exactly. Idempotent and resumable.
  #
  # Goes through the same sync path as live creation, so host hooks
  # (Raif.config.inference_cost_event_metadata) fire for backfilled events too.
  def self.backfill!(batch_size: 500)
    failed_model_completion_ids = []

    Raif::ModelCompletion
      .left_joins(:raif_inference_cost_event)
      .where("raif_inference_cost_events.id IS NULL OR raif_inference_cost_events.updated_at < raif_model_completions.updated_at")
      .where("completed_at IS NOT NULL OR failed_at IS NOT NULL")
      .in_batches(of: batch_size) do |batch|
        completions = begin
          batch.includes(:source).to_a
        rescue ActiveRecord::SubclassNotFound, NameError
          # A source row whose STI type no longer exists in the host app
          # (SubclassNotFound), or a source_type whose class was removed
          # entirely (NameError), makes the whole polymorphic preload raise.
          # Fall back to lazy per-record source loads for this batch; each
          # record's sync handles its own source resolution failure.
          batch.to_a
        end

        # enqueue_repair_on_failure: false because this IS the repair path; a
        # persistently failing record must not enqueue another full run per
        # failure (failures still report via Rails.error).
        completions.each do |model_completion|
          synced = model_completion.send(:sync_inference_cost_event, enqueue_repair_on_failure: false)

          event = model_completion.raif_inference_cost_event
          if synced && event&.persisted?
            begin
              # A stale-but-accurate event gets no timestamp bump from the
              # sync's save! (no attribute changed), so certify its freshness
              # explicitly: the archive job's eligibility guard reads
              # event.updated_at >= completion.updated_at. Only after a
              # successful sync - certifying an event whose re-sync failed
              # would mark stale spend data safe to cull.
              event.touch if event.updated_at < model_completion.updated_at
            rescue StandardError => e
              # Certification is part of the per-record repair operation: a
              # transient touch failure must accumulate like a sync failure
              # (raising the retryable aggregate error below) rather than
              # escape raw and abort the rest of the batch.
              Rails.error.report(e, handled: true, severity: :error)
              failed_model_completion_ids << model_completion.id
            end
          else
            failed_model_completion_ids << model_completion.id
          end
        end
      end

    return if failed_model_completion_ids.empty?

    # Per-record failures were already reported via Rails.error; raising here
    # makes the run itself fail so callers see the partial failure - the rake
    # task exits non-zero and Raif::RepairInferenceCostEventsJob gets bounded
    # retries from its queue backend instead of reporting success with events
    # still missing.
    raise Raif::Errors::InferenceCostEventsBackfillError,
      "Failed to create or re-sync inference cost events for #{failed_model_completion_ids.size} model completion(s) " \
        "(ids: #{failed_model_completion_ids.first(20).join(", ")}#{failed_model_completion_ids.size > 20 ? ", ..." : ""})"
  end

  # Column check, not a query: the FK is nullified at the DB level the moment
  # the completion row is deleted.
  def model_completion_live?
    raif_model_completion_id.present?
  end
end
