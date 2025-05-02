# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Task, type: :model do
  describe "#requested_language_key" do
    it "does not permit invalid language keys" do
      task = FB.build(:raif_task, requested_language_key: "invalid")
      expect(task.valid?).to eq(false)
      expect(task.errors[:requested_language_key]).to include("is not included in the list")
    end
  end

  describe "#llm_model_key" do
    it "does not permit invalid model names" do
      task = FB.build(:raif_task, llm_model_key: "invalid")
      expect(task.valid?).to eq(false)
      expect(task.errors[:llm_model_key]).to include("is not included in the list")
    end
  end

  describe ".run" do
    let(:user) { FB.create(:raif_test_user) }
    context "for a task requesting a text response" do
      before do
        stub_raif_task(Raif::TestTask) do |_messages|
          "Why is a pirate's favorite letter 'R'? Because, if you think about it, 'R' is the only letter that makes sense."
        end
      end

      context "when no language preference is set" do
        it "runs the task" do
          task = Raif::TestTask.run(creator: user)
          expect(task).to be_persisted
          expect(task.creator).to eq(user)
          expect(task.started_at).to be_present
          expect(task.completed_at).to be_present
          expect(task.prompt).to eq("Tell me a joke")
          expect(task.system_prompt).to eq("You are a helpful assistant.\nYou are also good at telling jokes.")
          expect(task.response_format).to eq("text")
          expect(task.raw_response).to eq("Why is a pirate's favorite letter 'R'? Because, if you think about it, 'R' is the only letter that makes sense.") # rubocop:disable Layout/LineLength
          expect(task.parsed_response).to eq("Why is a pirate's favorite letter 'R'? Because, if you think about it, 'R' is the only letter that makes sense.") # rubocop:disable Layout/LineLength
          expect(task.requested_language_key).to be_nil

          expect(task.raif_model_completion).to be_persisted
          expect(task.raif_model_completion.source).to eq(task)
          expect(task.raif_model_completion.temperature).to eq(0.5) # Raif::TestTask sets the temperature to 0.5
          expect(task.raif_model_completion.raw_response).to eq("Why is a pirate's favorite letter 'R'? Because, if you think about it, 'R' is the only letter that makes sense.") # rubocop:disable Layout/LineLength
        end
      end

      context "when a language preference is set" do
        it "runs the task" do
          task = Raif::TestTask.run(creator: user, requested_language_key: "es")
          expect(task).to be_persisted
          expect(task.creator).to eq(user)
          expect(task.started_at).to be_present
          expect(task.completed_at).to be_present
          expect(task.prompt).to eq("Tell me a joke")
          expect(task.system_prompt).to eq("You are a helpful assistant.\nYou're collaborating with teammate who speaks Spanish. Please respond in Spanish.\nYou are also good at telling jokes.") # rubocop:disable Layout/LineLength
          expect(task.response_format).to eq("text")
          expect(task.raw_response).to eq("Why is a pirate's favorite letter 'R'? Because, if you think about it, 'R' is the only letter that makes sense.") # rubocop:disable Layout/LineLength
          expect(task.parsed_response).to eq("Why is a pirate's favorite letter 'R'? Because, if you think about it, 'R' is the only letter that makes sense.") # rubocop:disable Layout/LineLength
          expect(task.requested_language_key).to eq("es")

          expect(task.raif_model_completion).to be_persisted
          expect(task.raif_model_completion.source).to eq(task)
          expect(task.raif_model_completion.temperature).to eq(0.5) # Raif::TestTask sets the temperature to 0.5
          expect(task.raif_model_completion.raw_response).to eq("Why is a pirate's favorite letter 'R'? Because, if you think about it, 'R' is the only letter that makes sense.") # rubocop:disable Layout/LineLength
        end
      end

      context "when the creator has a language preference" do
        it "runs the task" do
          allow(user).to receive(:preferred_language_key).and_return("de")
          task = Raif::TestTask.run(creator: user)
          expect(task).to be_persisted
          expect(task.creator).to eq(user)
          expect(task.started_at).to be_present
          expect(task.completed_at).to be_present
          expect(task.prompt).to eq("Tell me a joke")
          expect(task.system_prompt).to eq("You are a helpful assistant.\nYou're collaborating with teammate who speaks German. Please respond in German.\nYou are also good at telling jokes.") # rubocop:disable Layout/LineLength
          expect(task.response_format).to eq("text")
          expect(task.raw_response).to eq("Why is a pirate's favorite letter 'R'? Because, if you think about it, 'R' is the only letter that makes sense.") # rubocop:disable Layout/LineLength
          expect(task.parsed_response).to eq("Why is a pirate's favorite letter 'R'? Because, if you think about it, 'R' is the only letter that makes sense.") # rubocop:disable Layout/LineLength
          expect(task.requested_language_key).to eq("de")

          expect(task.raif_model_completion).to be_persisted
          expect(task.raif_model_completion.source).to eq(task)
          expect(task.raif_model_completion.temperature).to eq(0.5) # Raif::TestTask sets the temperature to 0.5
          expect(task.raif_model_completion.raw_response).to eq("Why is a pirate's favorite letter 'R'? Because, if you think about it, 'R' is the only letter that makes sense.") # rubocop:disable Layout/LineLength
        end
      end
    end

    context "for a task requesting a JSON response" do
      before do
        stub_raif_task(Raif::TestJsonTask) do |_messages|
          {
            joke: "Why is a pirate's favorite letter 'R'? Because, if you think about it, 'R' is the only letter that makes sense.",
            answer: "R"
          }.to_json
        end
      end

      it "runs the task" do
        task = Raif::TestJsonTask.run(creator: user)
        expect(task).to be_persisted
        expect(task.creator).to eq(user)
        expect(task.started_at).to be_present
        expect(task.completed_at).to be_present
        expect(task.prompt).to eq("Tell me a joke")
        expect(task.system_prompt).to eq("You are a helpful assistant.\nYou are also good at telling jokes. Your response should be a JSON object with the following keys: joke, answer.") # rubocop:disable Layout/LineLength
        expect(task.response_format).to eq("json")
        expect(task.raw_response).to eq("{\"joke\":\"Why is a pirate's favorite letter 'R'? Because, if you think about it, 'R' is the only letter that makes sense.\",\"answer\":\"R\"}") # rubocop:disable Layout/LineLength

        expect(task.raif_model_completion).to be_persisted
        expect(task.raif_model_completion.source).to eq(task)
        expect(task.raif_model_completion.temperature).to eq(0.75) # Raif::TestJsonTask sets the temperature to 0.75
        expect(task.raif_model_completion.raw_response).to eq("{\"joke\":\"Why is a pirate's favorite letter 'R'? Because, if you think about it, 'R' is the only letter that makes sense.\",\"answer\":\"R\"}") # rubocop:disable Layout/LineLength
      end
    end

    context "for a task requesting an HTML response" do
      before do
        stub_raif_task(Raif::TestHtmlTask) do |_messages|
          "<p>Why is a pirate's favorite letter 'R'?</p><p>Because, if you think about it, <strong style='color: red;'>'R'</strong> is the only letter that makes sense.</p>" # rubocop:disable Layout/LineLength
        end
      end

      it "runs the task" do
        task = Raif::TestHtmlTask.run(creator: user)
        expect(task).to be_persisted
        expect(task.creator).to eq(user)
        expect(task.started_at).to be_present
        expect(task.completed_at).to be_present
        expect(task.prompt).to eq("Tell me a joke")
        expect(task.system_prompt).to eq("You are a helpful assistant.\nYou are also good at telling jokes. Your response should be an HTML snippet that is formatted with basic HTML tags.") # rubocop:disable Layout/LineLength
        expect(task.response_format).to eq("html")
        expect(task.raw_response).to eq("<p>Why is a pirate's favorite letter 'R'?</p><p>Because, if you think about it, <strong style='color: red;'>'R'</strong> is the only letter that makes sense.</p>") # rubocop:disable Layout/LineLength

        expect(task.raif_model_completion).to be_persisted
        expect(task.raif_model_completion.source).to eq(task)
        expect(task.raif_model_completion.temperature).to eq(0.7) # Raif::TestHtmlTask doesn't set a temperature, so it inherits the default
        expect(task.raif_model_completion.raw_response).to eq("<p>Why is a pirate's favorite letter 'R'?</p><p>Because, if you think about it, <strong style='color: red;'>'R'</strong> is the only letter that makes sense.</p>") # rubocop:disable Layout/LineLength
      end
    end

    context "when including an image" do
      it "runs the task" do
        stub_raif_task(Raif::TestTask) do |_messages|
          "The image contains the Cultivate Labs logo."
        end

        image_path = Raif::Engine.root.join("spec/fixtures/files/cultivate.png")
        image = Raif::ModelImageInput.new(input: image_path)
        task = Raif::TestTask.run(creator: user, images: [image])

        expect(task).to be_persisted
        expect(task.prompt).to eq("Tell me a joke")
        expect(task.system_prompt).to eq("You are a helpful assistant.\nYou are also good at telling jokes.")
        expect(task.response_format).to eq("text")
        expect(task.raw_response).to eq("The image contains the Cultivate Labs logo.")

        expect(task.raif_model_completion).to be_persisted
        expect(task.raif_model_completion.source).to eq(task)
        expect(task.raif_model_completion.temperature).to eq(0.5) # Raif::TestTask sets the temperature to 0.5
        expect(task.raif_model_completion.raw_response).to eq("The image contains the Cultivate Labs logo.")
        expect(task.raif_model_completion.messages).to eq([
          {
            "role" => "user",
            "content" => [
              { "type" => "text", "text" => "Tell me a joke" },
              {
                "type" => "image_url",
                "image_url" => { "url" => "data:image/png;base64,#{image.base64_data}" }
              }
            ]
          }
        ])
      end
    end

    context "when including a PDF" do
      it "runs the task" do
        stub_raif_task(Raif::TestTask) do |_messages|
          "The PDF contains a test message"
        end

        pdf_path = Raif::Engine.root.join("spec/fixtures/files/test.pdf")
        pdf = Raif::ModelFileInput.new(input: pdf_path)
        task = Raif::TestTask.run(creator: user, files: [pdf])

        expect(task).to be_persisted
        expect(task.prompt).to eq("Tell me a joke")
        expect(task.system_prompt).to eq("You are a helpful assistant.\nYou are also good at telling jokes.")
        expect(task.response_format).to eq("text")
        expect(task.raw_response).to eq("The PDF contains a test message")

        expect(task.raif_model_completion).to be_persisted
        expect(task.raif_model_completion.source).to eq(task)
        expect(task.raif_model_completion.temperature).to eq(0.5) # Raif::TestTask sets the temperature to 0.5
        expect(task.raif_model_completion.raw_response).to eq("The PDF contains a test message")
        expect(task.raif_model_completion.messages).to eq([
          {
            "role" => "user",
            "content" => [
              { "type" => "text", "text" => "Tell me a joke" },
              {
                "type" => "file",
                "file" => {
                  "filename" => "test.pdf",
                  "file_data" => "data:application/pdf;base64,#{Base64.strict_encode64(File.read(pdf_path))}"
                }
              }
            ]
          }
        ])
      end
    end
  end

  describe "json_response_schema" do
    it "returns the json_response_schema when the class defines one" do
      schema = {
        type: "object",
        additionalProperties: false,
        required: ["joke", "answer"],
        properties: {
          joke: { type: "string" },
          answer: { type: "string" }
        }
      }

      expect(Raif::TestJsonTask.json_response_schema).to eq(schema)
      expect(Raif::TestJsonTask.new.json_response_schema).to eq(schema)
    end

    it "returns nil when the class does not define a json_response_schema" do
      expect(Raif::TestTask.json_response_schema).to be_nil
      expect(Raif::TestTask.new.json_response_schema).to be_nil
    end
  end
end
