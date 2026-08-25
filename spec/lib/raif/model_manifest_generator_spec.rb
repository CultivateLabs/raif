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

  # The generated source starts with a top-level `module Raif`; eval'd as-is
  # it would redefine the REAL ::Raif.default_llms for the rest of the suite,
  # since lib/raif/default_llms.rb defines that same method. We rename that
  # line to a fresh top-level constant and eval at
  # TOPLEVEL_BINDING rather than via Module#module_eval on an anonymous
  # module: an anonymous receiver would nest Module.nesting under itself, so
  # bare `Raif::Llms::Anthropic` / `Date` references inside the method
  # bodies would look for a same-named constant there and raise NameError
  # instead of falling through to the real top-level constants, which is
  # what a plain top-level rename preserves.
  def eval_isolated_default_llms_module(source)
    sandbox_const_name = :RaifGeneratorSpecSandbox
    isolated_source = source.sub(/^module Raif$/, "module #{sandbox_const_name}")
    raise "sandbox rename did not match source" if isolated_source == source

    eval(isolated_source, TOPLEVEL_BINDING, "generated_default_llms_spec.rb")
    sandbox_module = Object.const_get(sandbox_const_name)
    Object.send(:remove_const, sandbox_const_name)
    sandbox_module
  end

  describe ".default_llms_rb" do
    subject(:source) { described_class.default_llms_rb(manifest) }

    it "includes the generated file header" do
      expect(source).to include("# frozen_string_literal: true")
      expect(source).to include("# GENERATED FILE - DO NOT EDIT.")
      expect(source).to include("# Source of truth: model_manifest/*.rb")
      expect(source).to include("# Regenerate with: bin/generate_llm_registry")
    end

    it "emits cost literals as the raw manifest float divided by 1_000_000, never %g" do
      expect(source).to include("input_token_cost: 3.0 / 1_000_000,")
      expect(source).to include("output_token_cost: 15.0 / 1_000_000,")
    end

    it "emits a Float literal even when the manifest pricing is an Integer, so it never floors to 0" do
      integer_priced_entry = Raif::ModelManifest::Entry.new(
        key: :integer_priced_test_model,
        provider_name: "anthropic",
        endpoint: nil,
        adapter_class_name: "Raif::Llms::Anthropic",
        api_name: "integer-priced-test-1",
        display_name: "Integer Priced Test Model",
        max_completion_tokens: nil,
        pricing: { input_per_million: 3, output_per_million: 15 },
        capabilities: {
          temperature: true,
          structured_outputs: false,
          native_tool_use: true,
          streaming: true,
          batch_inference: true,
          images: false,
          pdfs: false,
          provider_managed_tools: []
        },
        lifecycle: { status: :active },
        source_path: "spec/fixtures/model_manifest/anthropic.yml",
        key_base: "integer_priced_test_model"
      )
      integer_priced_manifest = Raif::ModelManifest::Manifest.new(
        llm_entries: [integer_priced_entry], embedding_entries: [], provider_references: {}, provider_files: {}
      )

      integer_source = described_class.default_llms_rb(integer_priced_manifest)

      expect(integer_source).to include("input_token_cost: 3.0 / 1_000_000,")
      expect(integer_source).to include("output_token_cost: 15.0 / 1_000_000")
    end

    it "emits deprecation fields for a deprecated model and omits nil migration_note" do
      expect(source).to include("key: :anthropic_old_model,")
      expect(source).to include("deprecated: true,")
      expect(source).to include("retirement_date: Date.new(2026, 12, 1),")
      expect(source).to include("replacement_key: :anthropic_test_model")
      expect(source).not_to include("migration_note:")
    end

    it "omits retired models entirely" do
      expect(source).not_to include("gpt_gone")
    end

    it "emits max_completion_tokens with underscore separators" do
      expect(source).to include("max_completion_tokens: 64_000,")
    end

    it "emits model_provider_settings inline" do
      expect(source).to include("model_provider_settings: { supports_temperature: false },")
    end

    it "emits supported_provider_managed_tools as a multiline array of constants" do
      expect(source).to include("supported_provider_managed_tools: [\n")
      expect(source).to include("Raif::ModelTools::ProviderManaged::WebSearch,\n")
      expect(source).to include("Raif::ModelTools::ProviderManaged::CodeExecution\n")
    end

    it "defines Raif.default_llms and Raif.default_streaming_unsupported_model_keys" do
      expect(source).to include("def self.default_llms")
      expect(source).to include("def self.default_streaming_unsupported_model_keys")
    end
  end

  describe ".default_embedding_models_rb" do
    subject(:source) { described_class.default_embedding_models_rb(manifest) }

    it "includes the generated file header and default_embedding_models method" do
      expect(source).to include("# GENERATED FILE - DO NOT EDIT.")
      expect(source).to include("def self.default_embedding_models")
    end

    it "emits the fixture embedding model with its raw cost literal" do
      expect(source).to include("key: :open_ai_test_embedding,")
      expect(source).to include("input_token_cost: 0.02 / 1_000_000,")
      expect(source).to include("default_output_vector_size: 1536")
    end

    it "emits a Float literal even when the manifest's input_per_million is an Integer" do
      integer_priced_entry = Raif::ModelManifest::EmbeddingEntry.new(
        key: :integer_priced_test_embedding,
        provider_name: "open_ai",
        adapter_class_name: "Raif::EmbeddingModels::OpenAi",
        api_name: "integer-priced-test-embedding",
        display_name: "Integer Priced Test Embedding",
        input_per_million: 2,
        default_output_vector_size: 1536,
        lifecycle: { status: :active },
        source_path: "spec/fixtures/model_manifest/embeddings.yml"
      )
      integer_priced_manifest = Raif::ModelManifest::Manifest.new(
        llm_entries: [], embedding_entries: [integer_priced_entry], provider_references: {}, provider_files: {}
      )

      integer_source = described_class.default_embedding_models_rb(integer_priced_manifest)

      expect(integer_source).to include("input_token_cost: 2.0 / 1_000_000,")
    end
  end

  describe ".model_names_yaml_block" do
    subject(:block) { described_class.model_names_yaml_block(manifest) }

    it "includes the 4-space indented header line" do
      expect(block.lines.first).to eq("    model_names:\n")
    end

    it "includes the injected raif_test_llm name" do
      expect(block).to include("      raif_test_llm: Raif Test LLM\n")
    end

    it "is alphabetically sorted by key" do
      keys = block.lines.drop(1).map { |line| line.strip.split(":").first }
      expect(keys).to eq(keys.sort)
    end

    it "does not include retired models" do
      expect(block).not_to include("gpt_gone")
    end
  end

  describe ".embedding_model_names_yaml_block" do
    subject(:block) { described_class.embedding_model_names_yaml_block(manifest) }

    it "includes the 4-space indented header line and the fixture embedding model" do
      expect(block.lines.first).to eq("    embedding_model_names:\n")
      expect(block).to include("      open_ai_test_embedding: OpenAI Test Embedding\n")
    end
  end

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

  describe ".write_all!" do
    # Runs against tmpdir stand-ins, not the real repo files, so the spec never
    # mutates checked-in files on disk. These mimic just enough of the real
    # file shapes (marker pairs / YAML sections) to exercise the rewriter
    # logic, pointed at via write_all!'s `root:` kwarg.
    around do |example|
      Dir.mktmpdir("raif-generator-spec") do |dir|
        @tmp_root = dir
        setup_tmp_root!(dir)
        example.run
      end
    end

    def setup_tmp_root!(dir)
      FileUtils.mkdir_p(File.join(dir, "lib/raif"))
      FileUtils.mkdir_p(File.join(dir, "config/locales"))
      FileUtils.mkdir_p(File.join(dir, "lib/generators/raif/install/templates"))
      FileUtils.mkdir_p(File.join(dir, "docs/_getting_started"))

      File.write(File.join(dir, "config/locales/en.yml"), <<~YAML)
        ---
        en:
          raif:
            embedding_model_names:
              placeholder_embedding: Placeholder Embedding
            model_names:
              placeholder_model: Placeholder Model
            other_key: unrelated
      YAML

      File.write(File.join(dir, "lib/generators/raif/install/templates/initializer.rb"), <<~RUBY)
        # frozen_string_literal: true

        Raif.configure do |config|
          # Available keys:
          # BEGIN GENERATED MODEL KEYS (bin/generate_llm_registry)
          #   placeholder_key
          # END GENERATED MODEL KEYS
          # config.default_llm_model_key = "open_ai_gpt_4o"

          # Available keys:
          # BEGIN GENERATED EMBEDDING MODEL KEYS (bin/generate_llm_registry)
          #   placeholder_embedding_key
          # END GENERATED EMBEDDING MODEL KEYS
          # config.default_embedding_model_key = "open_ai_text_embedding_3_small"
        end
      RUBY

      setup_md_sections = %w[open_ai open_ai_responses anthropic bedrock open_router google x_ai embeddings]
      setup_md_body = setup_md_sections.map do |section|
        <<~MD
          ## #{section}
          <!-- BEGIN GENERATED MODEL KEYS: #{section} -->
          - `placeholder`
          <!-- END GENERATED MODEL KEYS: #{section} -->
        MD
      end.join("\n")
      File.write(File.join(dir, "docs/_getting_started/setup.md"), setup_md_body)
    end

    def snapshot(dir)
      %w[
        lib/raif/default_llms.rb
        lib/raif/default_embedding_models.rb
        config/locales/en.yml
        lib/generators/raif/install/templates/initializer.rb
        docs/_getting_started/setup.md
      ].to_h { |relative| [relative, File.read(File.join(dir, relative))] }
    end

    it "writes all four target files" do
      described_class.write_all!(manifest, root: @tmp_root)

      expect(File).to exist(File.join(@tmp_root, "lib/raif/default_llms.rb"))
      expect(File).to exist(File.join(@tmp_root, "lib/raif/default_embedding_models.rb"))
    end

    it "rewrites the en.yml sections without markers" do
      described_class.write_all!(manifest, root: @tmp_root)
      content = File.read(File.join(@tmp_root, "config/locales/en.yml"))

      expect(content).to include("raif_test_llm: Raif Test LLM")
      expect(content).to include("open_ai_test_embedding: OpenAI Test Embedding")
      expect(content).to include("other_key: unrelated")
      expect(content).not_to include("placeholder_model")
    end

    it "rewrites the content between the initializer LLM markers" do
      described_class.write_all!(manifest, root: @tmp_root)
      content = File.read(File.join(@tmp_root, "lib/generators/raif/install/templates/initializer.rb"))

      expect(content).to include("#   anthropic_test_model")
      expect(content).not_to include("placeholder_key")
      expect(content).to include('config.default_llm_model_key = "open_ai_gpt_4o"')
    end

    it "rewrites the content between the initializer embedding markers" do
      described_class.write_all!(manifest, root: @tmp_root)
      content = File.read(File.join(@tmp_root, "lib/generators/raif/install/templates/initializer.rb"))

      expect(content).to include("#   open_ai_test_embedding")
      expect(content).not_to include("placeholder_embedding_key")
      expect(content).to include('config.default_embedding_model_key = "open_ai_text_embedding_3_small"')
    end

    it "rewrites the content between each setup.md marker pair" do
      described_class.write_all!(manifest, root: @tmp_root)
      content = File.read(File.join(@tmp_root, "docs/_getting_started/setup.md"))

      expect(content).to include("- `anthropic_test_model`")
      expect(content).to include("- `open_ai_test_embedding`")
      expect(content).not_to include("`placeholder`")
    end

    it "is idempotent: a second run changes nothing" do
      described_class.write_all!(manifest, root: @tmp_root)
      first_pass = snapshot(@tmp_root)

      described_class.write_all!(manifest, root: @tmp_root)
      second_pass = snapshot(@tmp_root)

      expect(second_pass).to eq(first_pass)
    end
  end

  # Permanent semantic safety net: proves the emitted Ruby literal text and
  # RegistryData's in-memory hash never drift apart. See
  # eval_isolated_default_llms_module above for how the eval is isolated.
  describe "generated default_llms.rb semantic equivalence" do
    it "evaluates to the same config data as RegistryData.llm_configs" do
      source = described_class.default_llms_rb(manifest)
      sandbox = eval_isolated_default_llms_module(source)

      # The emitted hash literal uses actual adapter Class objects as keys
      # (e.g. Raif::Llms::Anthropic => [...]), matching how the registry is
      # actually consumed at runtime. RegistryData.llm_configs groups by the
      # adapter's String class name instead, so key by name on both sides
      # to compare.
      actual = sandbox.default_llms.transform_keys(&:name)
      expected = Raif::ModelManifest::RegistryData.llm_configs(manifest)

      expect(actual.keys).to eq(expected.keys)

      expected.each do |adapter, expected_configs|
        actual_configs = actual.fetch(adapter)
        expect(actual_configs.map { |c| c[:key] }).to eq(expected_configs.map { |c| c[:key] })

        expected_configs.zip(actual_configs).each do |expected_config, actual_config|
          expect(actual_config[:api_name]).to eq(expected_config[:api_name])
          expect(actual_config[:input_token_cost]).to be_within(1e-12).of(expected_config[:input_token_cost])
          expect(actual_config[:output_token_cost]).to be_within(1e-12).of(expected_config[:output_token_cost])
          expect(actual_config[:max_completion_tokens]).to eq(expected_config[:max_completion_tokens])
          expect(actual_config.fetch(:model_provider_settings, {})).to eq(expected_config.fetch(:model_provider_settings, {}))
          expect(actual_config.fetch(:supported_provider_managed_tools, [])).to eq(
            expected_config.fetch(:supported_provider_managed_tools, [])
          )
          expect(actual_config[:deprecated]).to eq(expected_config[:deprecated])
          expect(actual_config[:retirement_date]).to eq(expected_config[:retirement_date])
          expect(actual_config[:replacement_key]).to eq(expected_config[:replacement_key])
          expect(actual_config[:migration_note]).to eq(expected_config[:migration_note])
        end
      end
    end

    it "evaluates default_streaming_unsupported_model_keys to a frozen array matching RegistryData" do
      source = described_class.default_llms_rb(manifest)
      sandbox = eval_isolated_default_llms_module(source)

      expect(sandbox.default_streaming_unsupported_model_keys).to eq(
        Raif::ModelManifest::RegistryData.streaming_unsupported_keys(manifest)
      )
      expect(sandbox.default_streaming_unsupported_model_keys).to be_frozen
    end
  end
end
