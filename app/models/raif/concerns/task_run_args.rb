# frozen_string_literal: true

module Raif::Concerns::TaskRunArgs
  extend ActiveSupport::Concern

  included do
    class_attribute :_task_run_args, instance_writer: false, default: []
  end

  class_methods do
    # DSL for declaring persistent task arguments that will be serialized to the database
    # @param name [Symbol] The name of the argument
    def task_run_arg(name)
      # Ensure each class has its own array copy
      self._task_run_args = _task_run_args.dup
      _task_run_args << name.to_sym

      # Define getter that pulls from task_run_args JSON
      define_method(name) do
        return instance_variable_get("@#{name}") if instance_variable_defined?("@#{name}")

        value = task_run_args&.dig(name.to_s)
        return unless value

        # Deserialize GID if it's a string starting with gid://
        deserialized = if value.is_a?(String) && value.start_with?("gid://")
          begin
            GlobalID::Locator.locate(value)
          rescue ActiveRecord::RecordNotFound
            nil
          end
        else
          value
        end

        instance_variable_set("@#{name}", deserialized)
      end

      # Define setter that stores in memory (for use during run)
      define_method("#{name}=") do |value|
        instance_variable_set("@#{name}", value)
      end
    end

    # Transform run args into a hash that can be stored in the task_run_args database column
    def serialize_task_run_args(args)
      serialized_args = {}
      _task_run_args.each do |arg_name|
        next unless args.key?(arg_name)

        value = args[arg_name]
        serialized_args[arg_name.to_s] = if value.respond_to?(:to_global_id)
          value.to_global_id.to_s
        else
          value
        end
      end

      serialized_args
    end
  end
end
