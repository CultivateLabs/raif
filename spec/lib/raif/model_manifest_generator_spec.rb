# frozen_string_literal: true

require "rails_helper"
require "raif/model_manifest"
require "raif/model_manifest/registry_data"
require "raif/model_manifest/generator"
require "tmpdir"
require "fileutils"

RSpec.describe Raif::ModelManifest::Generator do
  let(:fixture_dir) { Raif::Engine.root.join("spec/fixtures/model_manifest").to_s }
  let(:manifest) { Raif::ModelManifest.load(dir: fixture_dir) }

  describe ".replace_yaml_section" do
    it "replaces the header line through the last consecutive 6-space indented line" do
      content = <<~YAML
        en:
          raif:
            model_names:
              alpha_key: Alpha Name
              beta_key: Beta Name
            other_key: unrelated
      YAML

      replacement = "    model_names:\n      new_key: New Value\n"
      result = described_class.replace_yaml_section(content, "model_names", replacement)

      expect(result).to eq(<<~YAML)
        en:
          raif:
            model_names:
              new_key: New Value
            other_key: unrelated
      YAML
    end
  end

  describe ".replace_between_markers" do
    it "replaces only the content strictly between the marker lines" do
      content = <<~TXT
        before
        # BEGIN X
        old line 1
        old line 2
        # END X
        after
      TXT

      result = described_class.replace_between_markers(content, "# BEGIN X", "# END X", "new line 1\nnew line 2\n")

      expect(result).to eq(<<~TXT)
        before
        # BEGIN X
        new line 1
        new line 2
        # END X
        after
      TXT
    end
  end

  describe ".initializer_keys_block" do
    it "emits one comment line per LLM key, indented to match the surrounding comment block" do
      block = described_class.initializer_keys_block(manifest)
      expect(block).to include("  #   anthropic_test_model\n")
      expect(block).to include("  #   open_ai_gpt_test\n")
      expect(block).not_to include("gpt_gone")
    end
  end

  describe ".initializer_embedding_keys_block" do
    it "emits one comment line per embedding key, in the same format as the LLM block" do
      block = described_class.initializer_embedding_keys_block(manifest)
      expect(block).to eq("  #   open_ai_test_embedding\n")
    end
  end

  describe ".setup_md_keys_block" do
    it "emits a markdown bullet per key for a provider section" do
      block = described_class.setup_md_keys_block(manifest, "anthropic")
      expect(block).to eq("- `anthropic_test_model`\n- `anthropic_old_model`\n")
    end

    it "emits a markdown bullet per key for the embeddings section" do
      block = described_class.setup_md_keys_block(manifest, "embeddings")
      expect(block).to eq("- `open_ai_test_embedding`\n")
    end

    it "returns an empty string for a provider with no fixture models" do
      expect(described_class.setup_md_keys_block(manifest, "bedrock")).to eq("")
    end
  end
end
