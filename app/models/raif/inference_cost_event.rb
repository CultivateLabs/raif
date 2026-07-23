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
#  raif_model_completion_batch_id :bigint
#  raif_model_completion_id       :bigint
#  source_id                      :bigint
#
# Indexes
#
#  index_raif_inference_cost_events_on_incurred_at                (incurred_at)
#  index_raif_inference_cost_events_on_original_completion_id     (original_model_completion_id)
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

  validates :original_model_completion_id, presence: true
  validates :llm_model_key, presence: true
  validates :model_api_name, presence: true
  validates :incurred_at, presence: true

  after_initialize -> { self.metadata ||= {} }

  # Creates events for terminal completions that don't have one yet. The bulk
  # one-time entry point after upgrading (see the raif:backfill_inference_cost_events
  # rake task); Raif::RepairInferenceCostEventsJob runs the same operation as
  # steady-state self-healing. Terminal-only: pending completions have NULL
  # tokens and contribute nothing to sums, so event sums equal completion sums
  # exactly. Idempotent and resumable via where.missing.
  #
  # Goes through the same sync path as live creation, so host hooks
  # (Raif.config.inference_cost_event_metadata) fire for backfilled events too.
  def self.backfill!(batch_size: 500)
    Raif::ModelCompletion
      .where.missing(:raif_inference_cost_event)
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

        completions.each { |model_completion| model_completion.send(:sync_inference_cost_event) }
      end
  end

  # Column check, not a query: the FK is nullified at the DB level the moment
  # the completion row is deleted.
  def model_completion_live?
    raif_model_completion_id.present?
  end
end
