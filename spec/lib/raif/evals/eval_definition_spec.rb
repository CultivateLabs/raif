# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Evals::EvalDefinition do
  def definition_for(eval_set_class, description)
    eval_set_class.evals.find { |definition| definition.description == description }
  end

  describe "#id" do
    let(:eval_set_class) do
      named_eval_set("SummarizationEvalSet") do
        eval "summarizes the article" do
          expect("passes") { true }
        end
      end
    end

    it "is the eval set's name, a slug of the description, and a digest over both" do
      expect(definition_for(eval_set_class, "summarizes the article").id)
        .to match(/\ASummarizationEvalSet#summarizes-the-article-[0-9a-f]{12}\z/)
    end

    it "is stable across processes, so two runs of the same eval produce the same id" do
      other_class = named_eval_set("SummarizationEvalSet2") do
        eval "summarizes the article" do
          expect("passes") { true }
        end
      end

      # Same name, so the same digest input: an id has to survive the file being edited, not the
      # class object being rebuilt.
      allow(other_class).to receive(:name).and_return("SummarizationEvalSet")

      expect(definition_for(other_class, "summarizes the article").id)
        .to eq(definition_for(eval_set_class, "summarizes the article").id)
    end

    it "does not change when an eval is added above it" do
      before_insert = definition_for(eval_set_class, "summarizes the article").id

      after_insert = named_eval_set("SummarizationEvalSet3") do
        eval "a new eval at the top" do
          expect("passes") { true }
        end

        eval "summarizes the article" do
          expect("passes") { true }
        end
      end

      allow(after_insert).to receive(:name).and_return("SummarizationEvalSet")
      definition = definition_for(after_insert, "summarizes the article")

      expect(definition.index).to eq(1)
      expect(definition.id).to eq(before_insert)
    end

    it "namespaces the id by eval set, so the same description in two sets is two ids" do
      other_set = named_eval_set("OtherEvalSet") do
        eval "summarizes the article" do
          expect("passes") { true }
        end
      end

      expect(definition_for(other_set, "summarizes the article").id)
        .not_to eq(definition_for(eval_set_class, "summarizes the article").id)
    end

    # The digest is taken over the description verbatim, which is what lets the slug be lossy.
    it "distinguishes descriptions that slug to the same thing" do
      eval_set = named_eval_set("BoundaryEvalSet") do
        eval "handles > 100 items" do
          expect("passes") { true }
        end

        eval "handles < 100 items" do
          expect("passes") { true }
        end
      end

      ids = eval_set.evals.map(&:id)

      expect(ids.map { |id| id[/\A[^#]+#(.*)-[0-9a-f]{12}\z/, 1] }).to eq(["handles-100-items", "handles-100-items"])
      expect(ids.uniq.length).to eq(2)
    end

    it "caps the readable half at a word boundary" do
      eval_set = named_eval_set("LongEvalSet") do
        eval "retains the specific figures, dates, and named entities from the source rather than paraphrasing them" do
          expect("passes") { true }
        end
      end

      slug = eval_set.evals.first.id[/\A[^#]+#(.*)-[0-9a-f]{12}\z/, 1]

      expect(slug).to eq("retains-the-specific-figures-dates-and-named-entities-from")
      expect(slug.length).to be <= described_class::DESCRIPTION_SLUG_LIMIT
    end

    it "falls back to the digest alone when the description has no sluggable characters" do
      eval_set = named_eval_set("SymbolEvalSet") do
        eval "≥ ?" do
          expect("passes") { true }
        end
      end

      expect(eval_set.evals.first.id).to match(/\ASymbolEvalSet#[0-9a-f]{12}\z/)
    end

    it "uses a declared id in place of the derived half" do
      eval_set = named_eval_set("DeclaredEvalSet") do
        eval "wording that will change", id: "stable-key" do
          expect("passes") { true }
        end
      end

      expect(eval_set.evals.first.id).to eq("DeclaredEvalSet#stable-key")
    end

    # #<Class:0x...> changes every process, so ids would be unique per run and every comparison
    # would read NOT COMPARABLE with nothing to point at.
    it "refuses when the eval set was never assigned to a constant" do
      eval_set = Class.new(Raif::Evals::EvalSet) do
        eval "never gets a name" do
          expect("passes") { true }
        end
      end

      expect { eval_set.evals.first.id }.to raise_error(ArgumentError, /anonymous class/)
    end

    # `Foo = Class.new(EvalSet) { ... }` is still anonymous while its evals register.
    it "is computed on first use rather than at registration" do
      eval_set = Class.new(Raif::Evals::EvalSet) do
        eval "named after the fact" do
          expect("passes") { true }
        end
      end

      stub_const("NamedAfterTheFact", eval_set)

      expect(eval_set.evals.first.id).to start_with("NamedAfterTheFact#")
    end
  end

  describe "identity checks at registration" do
    it "refuses two evals in one set with the same description" do
      expect do
        Class.new(Raif::Evals::EvalSet) do
          eval "the same thing" do
            expect("passes") { true }
          end

          eval "the same thing" do
            expect("passes") { true }
          end
        end
      end.to raise_error(ArgumentError, /already has an eval described as "the same thing"/)
    end

    it "allows a repeated description when one of them declares an id" do
      eval_set = named_eval_set("RepeatedDescriptionEvalSet") do
        eval "the same thing" do
          expect("passes") { true }
        end

        eval "the same thing", id: "the-same-thing-but-stricter" do
          expect("passes") { true }
        end
      end

      expect(eval_set.evals.map(&:id).uniq.length).to eq(2)
    end

    it "refuses two evals declaring the same id" do
      expect do
        Class.new(Raif::Evals::EvalSet) do
          eval "one", id: "shared" do
            expect("passes") { true }
          end

          eval "two", id: "shared" do
            expect("passes") { true }
          end
        end
      end.to raise_error(ArgumentError, /declares id "shared", which another eval/)
    end

    it "refuses an id that is not safe in a results file or on a command line" do
      expect do
        Class.new(Raif::Evals::EvalSet) do
          eval "spacey", id: "not a valid id" do
            expect("passes") { true }
          end
        end
      end.to raise_error(ArgumentError, /is not a valid eval id/)
    end

    it "allows the same description in two different eval sets" do
      first = named_eval_set("FirstEvalSet") do
        eval "the same thing" do
          expect("passes") { true }
        end
      end

      second = named_eval_set("SecondEvalSet") do
        eval "the same thing" do
          expect("passes") { true }
        end
      end

      expect(first.evals.first.id).not_to eq(second.evals.first.id)
    end
  end
end
