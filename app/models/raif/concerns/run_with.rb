# frozen_string_literal: true

module Raif::Concerns::RunWith
  extend ActiveSupport::Concern

  included do
    class_attribute :_run_with_args, instance_writer: false, default: []

    # Backward compatibility alias
    class_attribute :_task_run_args, instance_writer: false, default: []

    # Automatically serialize run_with args before validation on create
    before_validation :serialize_run_with_to_column, on: :create
  end

  class_methods do
    # DSL for declaring persistent run arguments that will be serialized to the database
    # @param name [Symbol] The name of the argument
    def run_with(name)
      # Ensure each class has its own array copy
      self._run_with_args = _run_with_args.dup
      _run_with_args << name.to_sym

      # Keep backward compatibility for _task_run_args class attribute
      self._task_run_args = _task_run_args.dup
      _task_run_args << name.to_sym

      # Define getter that pulls from run_with JSON column
      define_method(name) do
        return instance_variable_get("@#{name}") if instance_variable_defined?("@#{name}")

        value = run_with&.dig(name.to_s)
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

    # Backward compatibility alias
    alias_method :task_run_arg, :run_with

    # Transform run args into a hash that can be stored in the run_with database column
    def serialize_run_with(args)
      serialized_args = {}
      _run_with_args.each do |arg_name|
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

    # Backward compatibility alias
    alias_method :serialize_task_run_args, :serialize_run_with
  end

private

  # Automatically called before validation on create to serialize run_with args
  # Collects all declared run_with arguments from instance variables and serializes them
  # to the run_with JSON column
  def serialize_run_with_to_column
    args = {}

    # Collect all run_with args that were set via instance variables
    self.class._run_with_args.each do |arg_name|
      if instance_variable_defined?("@#{arg_name}")
        args[arg_name] = instance_variable_get("@#{arg_name}")
      end
    end

    # Merge serialized args into run_with hash if any args were set
    if args.any?
      self.run_with ||= {}
      self.run_with = self.run_with.merge(self.class.serialize_run_with(args))
    end
  end
end
