# frozen_string_literal: true

require "rails_helper"
require "stringio"
require Raif::Engine.root.join("script/smoke/terminal")
require Raif::Engine.root.join("script/smoke/report")

RSpec.describe Smoke::Report do
  def capability(status, detail: "detail")
    { status: status, detail: detail }
  end

  def model_result(key, **capabilities)
    { key: key, explicit: false, capabilities: capabilities.transform_keys(&:to_s).transform_values { |status| capability(status) } }
  end

  # $stdout swapped for a StringIO, whose #tty? is always false, so Smoke::Terminal's tty-based
  # color detection is naturally off here -- output is plain text, exactly what the label/shape
  # assertions below need, with no extra color stubbing.
  def capture_stdout
    out = StringIO.new
    original = $stdout
    $stdout = out
    yield
    out.string
  ensure
    $stdout = original
  end

  describe ".status_label" do
    it "maps :consistent to CONSISTENT" do
      expect(described_class.status_label(:consistent)).to eq("CONSISTENT")
    end

    it "maps every existing status to its known label" do
      expect(described_class.status_label(:pass)).to eq("PASS")
      expect(described_class.status_label(:fail)).to eq("FAIL")
      expect(described_class.status_label(:skip)).to eq("SKIP")
      expect(described_class.status_label(:timeout)).to eq("TIMEOUT")
      expect(described_class.status_label(:note)).to eq("NOTE")
    end

    it "upcases an unrecognized status as a fallback" do
      expect(described_class.status_label(:weird)).to eq("WEIRD")
    end
  end

  describe ".progress_summary" do
    it "renders a :consistent capability with the CONSISTENT label" do
      summary = described_class.progress_summary({ "temperature" => capability(:consistent) })

      expect(summary).to include("temperature=CONSISTENT")
    end
  end

  describe ".worst_model_status" do
    it "buckets a model whose only capability is :consistent as :consistent, not :fail" do
      expect(described_class.worst_model_status({ "temperature" => capability(:consistent) })).to eq(:consistent)
    end

    it "still buckets an empty capabilities hash as :fail (unexecuted required check)" do
      expect(described_class.worst_model_status({})).to eq(:fail)
    end

    it "ranks :fail as worse than :consistent" do
      capabilities = { "completion" => capability(:fail), "temperature" => capability(:consistent) }

      expect(described_class.worst_model_status(capabilities)).to eq(:fail)
    end

    it "ranks :consistent as worse than :pass (still worth surfacing ahead of a plain pass)" do
      capabilities = { "completion" => capability(:pass), "temperature" => capability(:consistent) }

      expect(described_class.worst_model_status(capabilities)).to eq(:consistent)
    end
  end

  describe ".print_text_matrix" do
    it "prints a blank line between the progress rows and the matrix header (Feature 2a)" do
      results = [model_result("anthropic_test_model", completion: :pass)]

      output = capture_stdout { described_class.print_text_matrix(results) }

      expect(output).to start_with("\n")
    end

    it "renders a CONSISTENT cell for a :consistent capability" do
      results = [model_result("anthropic_test_model", temperature: :consistent)]

      output = capture_stdout { described_class.print_text_matrix(results) }

      expect(output).to match(/anthropic_test_model\s+CONSISTENT/)
    end

    it "keeps a blank line before Details: when there are non-pass results" do
      results = [model_result("anthropic_test_model", completion: :fail)]

      output = capture_stdout { described_class.print_text_matrix(results) }

      expect(output).to include("\n\nDetails:\n")
    end

    it "includes a :consistent result in the Details section (it is not a :pass)" do
      results = [model_result("anthropic_test_model", temperature: :consistent, completion: :pass)]

      output = capture_stdout { described_class.print_text_matrix(results) }

      expect(output).to include("temperature: CONSISTENT")
    end

    it "prints nothing at all for an empty result set" do
      output = capture_stdout { described_class.print_text_matrix([]) }

      expect(output).to eq("")
    end
  end

  describe ".print_summary_footer" do
    it "includes a consistent count in the per-run counts line" do
      results = [model_result("anthropic_test_model", temperature: :consistent)]

      output = capture_stdout { described_class.print_summary_footer(results, 5, 0) }

      expect(output).to match(/\d+ consistent/)
    end
  end
end
