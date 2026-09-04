# frozen_string_literal: true

# The declaration surface that lib/raif/model_manifest/definitions/*.rb files are evaluated against.
#
# Manifest files are plain Ruby so they can use Date objects, symbols, and
# comments, but they are data, not scripts: each file is evaluated against a
# fresh BasicObject context that answers only `provider` and `embeddings`, and
# anything else it is asked for raises UnknownDeclaration instead of reaching
# Kernel. That keeps a manifest file from acquiring capabilities nobody meant
# to give it (requires, IO, mutating global state) by accident. It is not a
# sandbox: manifest files are reviewed code and could still break out.
#
# Builders collect declarations into frozen plain structs. Turning those
# declarations into Entry structs (adapter lookup, OpenAI endpoint expansion)
# is Raif::ModelManifest.load's job, and checking that the declared values make
# sense (known capabilities, live replacement targets) is the validity spec's.
require "date"

module Raif
  module ModelManifest
    module Dsl
      class UnknownDeclaration < StandardError; end

      ProviderDeclaration = Struct.new(:name, :references, :models, :source_path, keyword_init: true)

      # `capabilities` and `endpoints` are mutually exclusive: a model declares
      # capabilities for a single entry, or endpoints for one entry per
      # endpoint (see ProviderBuilder#model).
      ModelDeclaration = Struct.new(
        :key, :key_base, :api_name, :display_name, :max_completion_tokens,
        :pricing, :capabilities, :endpoints, :lifecycle, :source_path,
        keyword_init: true
      )

      EmbeddingProviderDeclaration = Struct.new(:name, :adapter_class_name, :models, :source_path, keyword_init: true)

      EmbeddingModelDeclaration = Struct.new(
        :key, :api_name, :display_name, :input_per_million,
        :default_output_vector_size, :lifecycle, :source_path,
        keyword_init: true
      )

      class << self
        # Manifest files are Ruby, so these hashes normally arrive symbol-keyed
        # already. Normalizing anyway means the entry shape consumers rely on
        # is guaranteed by the loader rather than by author discipline.
        def normalize_capabilities(capabilities)
          normalized = capabilities.transform_keys(&:to_sym)
          if normalized.key?(:provider_managed_tools)
            normalized[:provider_managed_tools] = Array(normalized[:provider_managed_tools]).map(&:to_sym)
          end

          deep_freeze(normalized)
        end

        # Every lifecycle field is always present, defaulting to nil, so
        # callers can read retirement_date or replacement_key off any entry
        # without first asking whether the model bothered to declare them.
        # replacement_key is symbolized alongside status because callers match
        # it against entry keys, which are symbols.
        def normalize_lifecycle(lifecycle)
          normalized = LIFECYCLE_KEYS.to_h { |key| [key, nil] }.merge(lifecycle.transform_keys(&:to_sym))
          normalized[:status] &&= normalized[:status].to_sym
          normalized[:replacement_key] &&= normalized[:replacement_key].to_sym
          deep_freeze(normalized)
        end

        def normalize_pricing(pricing)
          deep_freeze(pricing.transform_keys(&:to_sym))
        end

        # Endpoint names become strings because that is what the adapter and
        # key-prefix maps in ModelManifest are keyed by. Capabilities are the
        # only per-endpoint attribute; everything else is model level.
        def normalize_endpoints(endpoints, source_path:)
          endpoints.to_h do |endpoint, declaration|
            attributes = declaration.transform_keys(&:to_sym)
            unknown = attributes.keys - [:capabilities]
            unless unknown.empty?
              raise ArgumentError, "#{source_path}: endpoint #{endpoint.inspect} declares #{unknown.join(", ")}; only capabilities: is supported"
            end

            [endpoint.to_s, normalize_capabilities(attributes.fetch(:capabilities))]
          end.freeze
        end

        def deep_freeze(value)
          case value
          when Hash then value.to_h { |key, nested| [deep_freeze(key), deep_freeze(nested)] }.freeze
          when Array then value.map { |nested| deep_freeze(nested) }.freeze
          else value.freeze
          end
        end
      end

      # Collects one file's declarations. A fresh instance per file keeps a
      # manifest file from seeing (or corrupting) what another file declared.
      class Context < BasicObject
        # A BasicObject does not inherit Object's constant table, so Date has
        # to be reachable from here for `Date.new(2026, 8, 24)` in a manifest
        # file to resolve. It is deliberately the only constant a manifest file
        # can name unqualified.
        Date = ::Date

        attr_reader :providers, :embedding_providers

        def initialize
          @providers = []
          @embedding_providers = []
          @source_path = nil
        end

        # Evaluating with the file's real path means an exception raised from a
        # declaration points at the manifest line that caused it.
        def evaluate(source, source_path)
          @source_path = source_path
          instance_eval(source, source_path, 1)
          self
        end

        def provider(name, &block)
          builder = ProviderBuilder.new(name: name, source_path: @source_path)
          block.call(builder)
          @providers << builder.finish
        end

        def embeddings(&block)
          builder = EmbeddingRegistryBuilder.new(source_path: @source_path)
          block.call(builder)
          @embedding_providers.concat(builder.finish)
        end

        # No respond_to_missing? counterpart: BasicObject has no respond_to?
        # for it to answer.
        def method_missing(name, *_args)
          ::Kernel.raise UnknownDeclaration,
            "#{@source_path}: `#{name}` is not a manifest declaration; a manifest file may only declare `provider` and `embeddings`"
        end
      end

      class ProviderBuilder
        def initialize(name:, source_path:)
          @name = name.to_sym
          @source_path = source_path
          @references = {}
          @models = []
        end

        def references(**urls)
          @references = urls
        end

        # A model declares either `key:` with `capabilities:` (one entry), or
        # `key_base:` with `endpoints:` (one entry per endpoint, which is how
        # OpenAI models reach both the completions and responses adapters).
        def model(
          api_name:, display_name:, pricing:, lifecycle:,
          key: nil, key_base: nil, max_completion_tokens: nil, capabilities: nil, endpoints: nil
        )
          single_entry = !key.nil? && !capabilities.nil? && key_base.nil? && endpoints.nil?
          per_endpoint = !key_base.nil? && !endpoints.nil? && key.nil? && capabilities.nil?
          unless single_entry || per_endpoint
            raise ArgumentError, "#{@source_path}: #{display_name} must declare key: with capabilities:, or key_base: with endpoints:"
          end

          @models << ModelDeclaration.new(
            key: key&.to_sym,
            key_base: (key_base || key).to_s,
            api_name: api_name,
            display_name: display_name,
            max_completion_tokens: max_completion_tokens,
            pricing: Dsl.normalize_pricing(pricing),
            capabilities: capabilities && Dsl.normalize_capabilities(capabilities),
            endpoints: endpoints && Dsl.normalize_endpoints(endpoints, source_path: @source_path),
            lifecycle: Dsl.normalize_lifecycle(lifecycle),
            source_path: @source_path
          ).freeze
        end

        def finish
          ProviderDeclaration.new(
            name: @name,
            references: Dsl.deep_freeze(@references),
            models: @models.freeze,
            source_path: @source_path
          ).freeze
        end
      end

      class EmbeddingRegistryBuilder
        def initialize(source_path:)
          @source_path = source_path
          @providers = []
        end

        def provider(name, adapter:, &block)
          builder = EmbeddingProviderBuilder.new(name: name, adapter_class_name: adapter, source_path: @source_path)
          block.call(builder)
          @providers << builder.finish
        end

        def finish
          @providers.freeze
        end
      end

      class EmbeddingProviderBuilder
        def initialize(name:, adapter_class_name:, source_path:)
          @name = name.to_sym
          @adapter_class_name = adapter_class_name
          @source_path = source_path
          @models = []
        end

        def model(key:, api_name:, display_name:, input_per_million:, default_output_vector_size:, lifecycle:)
          @models << EmbeddingModelDeclaration.new(
            key: key.to_sym,
            api_name: api_name,
            display_name: display_name,
            input_per_million: input_per_million,
            default_output_vector_size: default_output_vector_size,
            lifecycle: Dsl.normalize_lifecycle(lifecycle),
            source_path: @source_path
          ).freeze
        end

        def finish
          EmbeddingProviderDeclaration.new(
            name: @name,
            adapter_class_name: @adapter_class_name,
            models: @models.freeze,
            source_path: @source_path
          ).freeze
        end
      end
    end
  end
end
