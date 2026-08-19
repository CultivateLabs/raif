# frozen_string_literal: true

require "raif/model_manifest"
require "raif/model_manifest/registry_data"

module Raif
  module ModelManifest
    # Turns RegistryData output into the checked-in artifacts: the two
    # generated Ruby registry files, the en.yml model name sections, the
    # initializer's "Available keys" comment block, and the setup.md
    # provider key lists. Emitters here are pure string builders; write_all!
    # is the only method that touches disk.
    module Generator
      GENERATED_HEADER = <<~RUBY.chomp
        # frozen_string_literal: true

        # GENERATED FILE - DO NOT EDIT.
        # Source of truth: model_manifest/*.yml
        # Regenerate with: bin/generate_llm_registry
      RUBY

      # setup.md section name => adapter class name, built from the same
      # source-of-truth maps ModelManifest uses to expand manifest entries,
      # so this can't drift from what actually produces each key.
      SECTION_ADAPTER_CLASS_NAMES = PROVIDER_ADAPTERS.merge(
        "open_ai" => OPEN_AI_ENDPOINT_ADAPTERS.fetch("completions"),
        "open_ai_responses" => OPEN_AI_ENDPOINT_ADAPTERS.fetch("responses")
      ).freeze

      SETUP_MD_SECTIONS = %w[open_ai open_ai_responses anthropic bedrock open_router google x_ai embeddings].freeze

      INITIALIZER_BEGIN_MARKER = "# BEGIN GENERATED MODEL KEYS (bin/generate_llm_registry)"
      INITIALIZER_END_MARKER = "# END GENERATED MODEL KEYS"
      INITIALIZER_EMBEDDING_BEGIN_MARKER = "# BEGIN GENERATED EMBEDDING MODEL KEYS (bin/generate_llm_registry)"
      INITIALIZER_EMBEDDING_END_MARKER = "# END GENERATED EMBEDDING MODEL KEYS"

      DEFAULT_LLMS_RELATIVE_PATH = "lib/raif/default_llms.rb"
      DEFAULT_EMBEDDING_MODELS_RELATIVE_PATH = "lib/raif/default_embedding_models.rb"
      LOCALE_EN_RELATIVE_PATH = "config/locales/en.yml"
      INITIALIZER_RELATIVE_PATH = "lib/generators/raif/install/templates/initializer.rb"
      SETUP_MD_RELATIVE_PATH = "docs/_getting_started/setup.md"

      class << self
        def default_llms_rb(manifest)
          entries_by_key = manifest.llm_entries.index_by(&:key)
          configs_by_adapter = RegistryData.llm_configs(manifest)

          adapter_blocks = ADAPTER_ORDER.filter_map do |adapter|
            configs = configs_by_adapter[adapter]
            next if configs.nil?

            adapter_block(adapter, configs, entries_by_key)
          end
          adapter_blocks[-1] = adapter_blocks[-1].sub(/,\z/, "") unless adapter_blocks.empty?

          lines = [GENERATED_HEADER, ""]
          lines << "module Raif"
          lines << "  def self.default_llms"
          lines << "    {"
          lines.concat(adapter_blocks)
          lines << "    }"
          lines << "  end"
          lines << ""
          lines << "  def self.default_streaming_unsupported_model_keys"
          lines << "    #{streaming_unsupported_literal(manifest)}.freeze"
          lines << "  end"
          lines << "end"
          "#{lines.join("\n")}\n"
        end

        def default_embedding_models_rb(manifest)
          entries_by_key = manifest.embedding_entries.index_by(&:key)
          configs_by_adapter = RegistryData.embedding_configs(manifest)

          adapter_blocks = configs_by_adapter.map do |adapter, configs|
            embedding_adapter_block(adapter, configs, entries_by_key)
          end
          adapter_blocks[-1] = adapter_blocks[-1].sub(/,\z/, "") unless adapter_blocks.empty?

          lines = [GENERATED_HEADER, ""]
          lines << "module Raif"
          lines << "  def self.default_embedding_models"
          lines << "    {"
          lines.concat(adapter_blocks)
          lines << "    }"
          lines << "  end"
          lines << "end"
          "#{lines.join("\n")}\n"
        end

        def model_names_yaml_block(manifest)
          yaml_section_block("model_names", RegistryData.model_names(manifest))
        end

        def embedding_model_names_yaml_block(manifest)
          yaml_section_block("embedding_model_names", RegistryData.embedding_model_names(manifest))
        end

        def initializer_keys_block(manifest)
          keys = RegistryData.llm_configs(manifest).values.flatten.map { |config| config[:key] }
          keys.map { |key| "  #   #{key}\n" }.join
        end

        def initializer_embedding_keys_block(manifest)
          keys = RegistryData.embedding_configs(manifest).values.flatten.map { |config| config[:key] }
          keys.map { |key| "  #   #{key}\n" }.join
        end

        def setup_md_keys_block(manifest, section)
          keys =
            if section == "embeddings"
              RegistryData.embedding_configs(manifest).values.flatten.map { |config| config[:key] }
            else
              adapter = SECTION_ADAPTER_CLASS_NAMES.fetch(section)
              RegistryData.llm_configs(manifest).fetch(adapter, []).map { |config| config[:key] }
            end

          keys.map { |key| "- `#{key}`\n" }.join
        end

        # Finds the line matching /^    #{section_key}:$/ (4-space indent) and
        # replaces it, and every immediately following line matching
        # /^      \S/ (6-space indent), with replacement_block (which already
        # includes the header line). Also used directly by the freshness spec.
        def replace_yaml_section(file_content, section_key, replacement_block)
          lines = file_content.lines
          header_pattern = /^    #{Regexp.escape(section_key)}:$/
          start_index = lines.index { |line| line.match?(header_pattern) }
          raise ArgumentError, "section #{section_key.inspect} not found" if start_index.nil?

          end_index = start_index + 1
          end_index += 1 while end_index < lines.length && lines[end_index].match?(/^      \S/)

          (lines[0...start_index] + block_lines(replacement_block) + lines[end_index..]).join
        end

        # Replaces the content strictly between (not including) the lines
        # containing begin_marker and end_marker. Also used directly by the
        # freshness spec.
        def replace_between_markers(file_content, begin_marker, end_marker, replacement)
          lines = file_content.lines
          begin_index = lines.index { |line| line.include?(begin_marker) }
          raise ArgumentError, "begin marker not found: #{begin_marker.inspect}" if begin_index.nil?

          offset = lines[(begin_index + 1)..].index { |line| line.include?(end_marker) }
          raise ArgumentError, "end marker not found: #{end_marker.inspect}" if offset.nil?

          end_index = begin_index + 1 + offset

          (lines[0..begin_index] + block_lines(replacement) + lines[end_index..]).join
        end

        def write_all!(manifest, root: Raif::Engine.root)
          root = root.to_s

          File.write(File.join(root, DEFAULT_LLMS_RELATIVE_PATH), default_llms_rb(manifest))
          File.write(File.join(root, DEFAULT_EMBEDDING_MODELS_RELATIVE_PATH), default_embedding_models_rb(manifest))
          write_locale_en!(manifest, root)
          write_initializer!(manifest, root)
          write_setup_md!(manifest, root)
        end

      private

        def write_locale_en!(manifest, root)
          path = File.join(root, LOCALE_EN_RELATIVE_PATH)
          content = File.read(path)
          content = replace_yaml_section(content, "model_names", model_names_yaml_block(manifest))
          content = replace_yaml_section(content, "embedding_model_names", embedding_model_names_yaml_block(manifest))
          File.write(path, content)
        end

        def write_initializer!(manifest, root)
          path = File.join(root, INITIALIZER_RELATIVE_PATH)
          content = File.read(path)
          content = replace_between_markers(content, INITIALIZER_BEGIN_MARKER, INITIALIZER_END_MARKER, initializer_keys_block(manifest))
          content = replace_between_markers(
            content, INITIALIZER_EMBEDDING_BEGIN_MARKER, INITIALIZER_EMBEDDING_END_MARKER, initializer_embedding_keys_block(manifest)
          )
          File.write(path, content)
        end

        def write_setup_md!(manifest, root)
          path = File.join(root, SETUP_MD_RELATIVE_PATH)
          content = File.read(path)
          SETUP_MD_SECTIONS.each do |section|
            content = replace_between_markers(
              content,
              "<!-- BEGIN GENERATED MODEL KEYS: #{section} -->",
              "<!-- END GENERATED MODEL KEYS: #{section} -->",
              setup_md_keys_block(manifest, section)
            )
          end
          File.write(path, content)
        end

        # An empty block yields no lines (an empty section collapses rather
        # than leaving a blank line); otherwise ensures a trailing newline
        # so it doesn't run into the line that follows it.
        def block_lines(block)
          return [] if block.empty?

          block.end_with?("\n") ? block.lines : "#{block}\n".lines
        end

        def yaml_section_block(section_key, names)
          lines = ["    #{section_key}:"]
          names.each { |key, value| lines << "      #{key}: #{yaml_scalar(value)}" }
          "#{lines.join("\n")}\n"
        end

        # Matches the current en.yml style: only quote when a plain scalar
        # would be ambiguous or lossy.
        def yaml_scalar(value)
          needs_quotes = value.include?(": ") || value.include?("#") || value != value.strip
          needs_quotes ? value.inspect : value
        end

        def adapter_block(adapter, configs, entries_by_key)
          literals = configs.map { |config| llm_config_literal(config, entries_by_key.fetch(config[:key]), 8) }
          "      #{adapter} => [\n#{literals.join(",\n")}\n      ],"
        end

        def embedding_adapter_block(adapter, configs, entries_by_key)
          literals = configs.map { |config| embedding_config_literal(config, entries_by_key.fetch(config[:key]), 8) }
          "      #{adapter} => [\n#{literals.join(",\n")}\n      ],"
        end

        def llm_config_literal(config, entry, indent)
          pad = " " * indent
          key_pad = " " * (indent + 2)
          field_lines = config.reject { |_, value| value.nil? }.map { |field, value| llm_config_field(field, value, entry, key_pad) }
          field_lines[-1] = field_lines[-1].sub(/,\z/, "")
          "#{pad}{\n#{field_lines.join("\n")}\n#{pad}}"
        end

        def llm_config_field(field, value, entry, pad)
          case field
          when :key then "#{pad}key: :#{value},"
          when :api_name then "#{pad}api_name: #{value.inspect},"
          when :input_token_cost then "#{pad}input_token_cost: #{entry.pricing.fetch("input_per_million")} / 1_000_000,"
          when :output_token_cost then "#{pad}output_token_cost: #{entry.pricing.fetch("output_per_million")} / 1_000_000,"
          when :max_completion_tokens then "#{pad}max_completion_tokens: #{underscored_integer(value)},"
          when :model_provider_settings then "#{pad}model_provider_settings: { #{inline_settings(value)} },"
          when :supported_provider_managed_tools then supported_provider_managed_tools_field(value, pad)
          when :supports_native_tool_use then "#{pad}supports_native_tool_use: #{value},"
          when :deprecated then "#{pad}deprecated: #{value},"
          when :retirement_date then "#{pad}retirement_date: Date.new(#{value.year}, #{value.month}, #{value.day}),"
          when :replacement_key then "#{pad}replacement_key: :#{value},"
          when :migration_note then "#{pad}migration_note: #{value.inspect},"
          else raise ArgumentError, "Generator: unknown llm config field #{field.inspect}"
          end
        end

        def supported_provider_managed_tools_field(tool_classes, pad)
          tool_pad = "#{pad}  "
          tool_lines = tool_classes.map { |klass| "#{tool_pad}#{klass.name}," }
          tool_lines[-1] = tool_lines[-1].sub(/,\z/, "")
          "#{pad}supported_provider_managed_tools: [\n#{tool_lines.join("\n")}\n#{pad}],"
        end

        def embedding_config_literal(config, entry, indent)
          pad = " " * indent
          key_pad = " " * (indent + 2)
          field_lines = config.reject { |_, value| value.nil? }.map { |field, value| embedding_config_field(field, value, entry, key_pad) }
          field_lines[-1] = field_lines[-1].sub(/,\z/, "")
          "#{pad}{\n#{field_lines.join("\n")}\n#{pad}}"
        end

        def embedding_config_field(field, value, entry, pad)
          case field
          when :key then "#{pad}key: :#{value},"
          when :api_name then "#{pad}api_name: #{value.inspect},"
          when :input_token_cost then "#{pad}input_token_cost: #{entry.input_per_million} / 1_000_000,"
          when :default_output_vector_size then "#{pad}default_output_vector_size: #{value},"
          else raise ArgumentError, "Generator: unknown embedding config field #{field.inspect}"
          end
        end

        def inline_settings(settings)
          settings.map { |key, value| "#{key}: #{value}" }.join(", ")
        end

        def streaming_unsupported_literal(manifest)
          keys = RegistryData.streaming_unsupported_keys(manifest)
          return "[]" if keys.empty?

          entries = keys.map { |key| "      #{key.inspect}" }
          "[\n#{entries.join(",\n")}\n    ]"
        end

        def underscored_integer(number)
          number.to_s.gsub(/(\d)(?=(\d{3})+$)/, '\1_')
        end
      end
    end
  end
end
