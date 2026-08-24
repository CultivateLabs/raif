# frozen_string_literal: true

module Raif
  # Archives Raif::ModelCompletion rows older than
  # Raif.config.model_completion_retention_period to
  # Raif.config.archive_storage as gzip JSONL (see Raif::ArchiveSerializer),
  # then deletes them, one Raif::Archive batch at a time. Raif::ArchiveJob
  # owns the batching, partitioning and cull machinery and documents the
  # invariants; this class contributes the eligibility rules.
  #
  # Deliberately NOT handled: raif_model_completion_batches rows remain; they
  # carry their own aggregated cost columns and nothing recomputes them from
  # children after finalization.
  class ArchiveModelCompletionsJob < ArchiveJob
    # Key prefix when partitioning is unset.
    KEY_PREFIX = "raif-archives/model-completions"
    # Resource segment below a partition prefix:
    # raif-archives/partitions/<token>/model-completions/<object>
    RESOURCE_KEY_SEGMENT = "model-completions"

    class << self
      def archived_class
        Raif::ModelCompletion
      end

      def retention_period
        Raif.config.model_completion_retention_period
      end

      def retention_config_name
        "model_completion_retention_period"
      end

      def key_prefix
        KEY_PREFIX
      end

      def resource_key_segment
        RESOURCE_KEY_SEGMENT
      end

      # A completion is safe to archive and delete only when ALL hold:
      #
      # - created_at is before the (job-frozen) retention cutoff
      # - it has been quiescent: not updated within QUIESCENCE_PERIOD
      #   (legitimately active months-old completions can't exist since batch
      #   lifetime is capped, but the guard is cheap insurance)
      # - it is not a member of a model completion batch that is still
      #   non-terminal (belt-and-suspenders alongside quiescence)
      # - durability guard, TERMINAL rows only: its Raif::InferenceCostEvent
      #   exists AND is at least as fresh as the completion
      #   (event.updated_at >= completion.updated_at). A post-terminal update
      #   whose event re-sync failed leaves a stale event that missing-only
      #   repair would never revisit, so the repair job also re-syncs stale
      #   events; until then the row just waits.
      # - nonterminal rows skip the durability guard: they never reached a
      #   terminal state, so no cost event exists and there is no spend to
      #   protect. These are orphaned pending rows from killed processes and
      #   crashed jobs (a third of one host's table in practice) that would
      #   otherwise be immortal. They are archived through the same path as
      #   everything else - NOT deleted outright, despite the temptation (no
      #   response, near-zero historical value): "every deleted completion
      #   exists in an archive" must hold without exception, and a
      #   delete-without-archive shortcut would be a second deletion
      #   semantics that weakens the invariant this job's safety rests on,
      #   to save pennies of mostly-redundant prompt storage.
      # - durable-citations guard: its citations, if any, have been copied to
      #   its Raif::ConversationEntry source (protects hosts that haven't run
      #   the conversation entry backfill)
      def eligible_scope(cutoff)
        quiescent_scope(cutoff)
          .where.not(id: active_batch_members)
          .where.not(id: terminal_without_fresh_cost_event(cutoff))
          .where.not(id: completions_with_uncopied_citations)
      end

      def dry_run_exclusions(cutoff)
        {
          excluded_by_active_batch: base_scope(cutoff).where(id: active_batch_members).count,
          excluded_missing_cost_event: terminal_scope(cutoff).where.not(id: completions_with_cost_event).count,
          excluded_stale_cost_event: terminal_scope(cutoff)
            .where(id: completions_with_cost_event)
            .where.not(id: completions_with_fresh_cost_event).count,
          excluded_uncopied_citations: base_scope(cutoff).where(id: completions_with_uncopied_citations).count
        }
      end

    private

      # Subquery, not a where.not(raif_model_completion_batch_id: ...)
      # clause: NOT IN mishandles the NULL batch ids most completions have.
      def active_batch_members
        Raif::ModelCompletion.where(
          raif_model_completion_batch_id: Raif::ModelCompletionBatch.non_terminal.select(:id)
        )
      end

      def completions_with_cost_event
        Raif::InferenceCostEvent.where.not(raif_model_completion_id: nil).select(:raif_model_completion_id)
      end

      # Events at least as fresh as their completion. An older event means a
      # post-terminal completion update committed but its event re-sync
      # failed: the durable spend data may be stale, so the row is not safe
      # to cull until the repair job re-syncs (or freshness-certifies) it.
      def completions_with_fresh_cost_event
        Raif::InferenceCostEvent
          .joins("INNER JOIN raif_model_completions ON raif_model_completions.id = raif_inference_cost_events.raif_model_completion_id")
          .where("raif_inference_cost_events.updated_at >= raif_model_completions.updated_at")
          .select(:raif_model_completion_id)
      end

      def terminal_without_fresh_cost_event(cutoff)
        terminal_scope(cutoff).where.not(id: completions_with_fresh_cost_event)
      end

      # Completions with citations whose Raif::ConversationEntry source has
      # an empty local citations column: culling them would erase citation
      # chips from historical conversations.
      def completions_with_uncopied_citations
        completion_citations_length = json_array_length_sql("raif_model_completions.citations")
        entry_citations_length = json_array_length_sql("raif_conversation_entries.citations")

        Raif::ModelCompletion
          .where(source_type: "Raif::ConversationEntry")
          .joins("INNER JOIN raif_conversation_entries ON raif_conversation_entries.id = raif_model_completions.source_id")
          .where("raif_model_completions.citations IS NOT NULL AND #{completion_citations_length} > 0")
          .where("raif_conversation_entries.citations IS NULL OR #{entry_citations_length} = 0")
      end

      # Table-qualified equivalent of
      # Raif::ApplicationRecord.where_json_not_blank, which can't be used
      # inside the entries join above (both tables have a citations column).
      def json_array_length_sql(qualified_column)
        case Raif::ModelCompletion.connection.adapter_name.downcase
        when "postgresql"
          "jsonb_array_length(#{qualified_column})"
        when "mysql2", "trilogy"
          "JSON_LENGTH(#{qualified_column})"
        else
          raise "Unsupported database: #{Raif::ModelCompletion.connection.adapter_name}"
        end
      end
    end

  private

    # original_model_completion_id retains record identity after the delete
    # nullifies the events' completion FK, so the stamp plus that column is
    # all a culled completion leaves behind.
    def stamp_cost_events!(archive, terminal_ids)
      stamped_count = Raif::InferenceCostEvent
        .where(raif_model_completion_id: terminal_ids)
        .update_all(raif_archive_id: archive.id)

      # The eligibility locks cover the completion rows, not their events: an
      # event deleted between the selection and the stamp would let a
      # terminal completion be culled without its durable spend record. The
      # stamped count proves every terminal row carries its stamp into
      # deletion; a mismatch rolls back stamps and deletes together.
      return if stamped_count == terminal_ids.size

      raise "#{self.class.name}: expected to stamp #{terminal_ids.size} cost event(s) for " \
        "archive ##{archive.id} but stamped #{stamped_count}; a cost event vanished between eligibility " \
        "selection and stamping - rolling back this cull"
    end

  end
end
