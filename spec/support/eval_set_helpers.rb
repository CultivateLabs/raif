# frozen_string_literal: true

module Raif
  # An eval's id is derived from the name of the eval set that declares it, so a set the specs
  # never assign to a constant has no identity and refuses to run. This names one for the duration
  # of the example, which is all `Class.new(Raif::Evals::EvalSet)` was ever missing.
  module EvalSetHelpers
    # @param name [String] the constant to stub the class onto. It only has to be distinct from
    #   other eval sets defined in the same example, since stub_const unwinds after each one.
    #
    # The body runs before the constant is assigned, so these specs also cover the host-app case of
    # `Foo = Class.new(Raif::Evals::EvalSet) { eval "..." }`.
    def named_eval_set(name = "TestEvalSet", parent: Raif::Evals::EvalSet, &body)
      eval_set_class = Class.new(parent, &body)
      stub_const(name, eval_set_class)
      eval_set_class
    end
  end
end

RSpec.configure do |config|
  config.include Raif::EvalSetHelpers
end
