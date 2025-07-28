# frozen_string_literal: true

RSpec.shared_examples "an agent" do |_parameter|
  describe "validations" do
    it "validates presence of task" do
      agent = described_class.new(
        creator: creator,
        system_prompt: "System prompt",
        max_iterations: 5,
        available_model_tools: [Raif::TestModelTool]
      )
      expect(agent).not_to be_valid
      expect(agent.errors[:task]).to include("can't be blank")
    end

    it "validates presence of system_prompt" do
      agent = described_class.new(
        creator: creator,
        task: "What is the capital of France?",
        max_iterations: 5,
        available_model_tools: [Raif::TestModelTool]
      )

      allow(agent).to receive(:build_system_prompt).and_return(nil)
      expect(agent).not_to be_valid
      expect(agent.errors[:system_prompt]).to include("can't be blank")
    end

    it "validates presence and numericality of max_iterations" do
      agent = described_class.new(
        creator: creator,
        task: "What is the capital of France?",
        system_prompt: "System prompt",
        available_model_tools: [Raif::TestModelTool]
      )
      expect(agent.max_iterations).to eq(10)
      expect(agent).to be_valid

      agent.max_iterations = nil
      expect(agent).not_to be_valid
      expect(agent.errors[:max_iterations]).to include("can't be blank")

      agent.max_iterations = 0
      expect(agent).not_to be_valid
      expect(agent.errors[:max_iterations]).to include("must be greater than 0")
    end
  end
end
