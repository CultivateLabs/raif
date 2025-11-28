# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_agents
#
#  id                     :bigint           not null, primary key
#  available_model_tools  :jsonb            not null
#  completed_at           :datetime
#  conversation_history   :jsonb            not null
#  creator_type           :string           not null
#  failed_at              :datetime
#  failure_reason         :text
#  final_answer           :text
#  iteration_count        :integer          default(0), not null
#  llm_model_key          :string           not null
#  max_iterations         :integer          default(10), not null
#  requested_language_key :string
#  run_with               :jsonb
#  source_type            :string
#  started_at             :datetime
#  system_prompt          :text
#  task                   :text
#  type                   :string           not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  creator_id             :bigint           not null
#  source_id              :bigint
#
# Indexes
#
#  index_raif_agents_on_created_at  (created_at)
#  index_raif_agents_on_creator     (creator_type,creator_id)
#  index_raif_agents_on_source      (source_type,source_id)
#
require "rails_helper"

RSpec.describe Raif::Agents::NativeToolCallingAgent, type: :model do
  let(:creator) { FB.create(:raif_test_user) }

  describe "#run!" do
    let(:task) { "What is the capital of France?" }
    let(:llm_model_key) { "open_ai_responses_gpt_4_1" }

    let(:agent) do
      described_class.new(
        creator: creator,
        source: creator,
        task: task,
        max_iterations: 5,
        available_model_tools: [Raif::ModelTools::WikipediaSearch, Raif::ModelTools::FetchUrl],
        llm_model_key: llm_model_key
      )
    end

    context "with OpenRouter/Gemini" do
      let(:task) { "Tell me some interesting facts from the James Webb Space Telescope's Wikipedia page" }
      let(:llm_model_key) { "open_router_gemini_2_5_flash" }

      it "processes multiple iterations until finding an answer",
        vcr: { cassette_name: "native_tool_calling_agent/open_router_gemini" } do
        expect(agent.started_at).to be_nil
        expect(agent.completed_at).to be_nil
        expect(agent.failed_at).to be_nil

        agent.run!

        expect(agent.started_at).to be_present
        expect(agent.completed_at).to be_present
        expect(agent.failed_at).to be_nil

        final_answer = "The James Webb Space Telescope (JWST) is a space telescope designed for infrared astronomy, making it the largest telescope in space. It's equipped with high-resolution and high-sensitivity instruments, allowing it to observe objects too old, distant, or faint for the Hubble Space Telescope. \n\nHere are some interesting facts about the JWST:\n\n*   **Infrared Focus:** Unlike Hubble, which observes in visible and ultraviolet light, Webb primarily observes in the infrared spectrum (0.6–28.5 μm). This allows it to see through cosmic dust and gas, observe colder objects like planets, and study the very early universe, as light from distant objects is redshifted into the infrared.\n*   **Massive Mirror:** Webb's primary mirror is 6.5 meters (21 ft) in diameter, composed of 18 hexagonal, gold-plated beryllium segments. This gives it a collecting area of about 25 square meters (270 sq ft), which is six times larger than Hubble's.\n*   **Extreme Cold:** To observe faint infrared light without interference from its own heat, the telescope must be kept extremely cold, below 50 K (−223 °C; −370 °F). A five-layer sunshield protects it from warming by the Sun, Earth, and Moon.\n*   **Distant Orbit:** Webb operates in a halo orbit around the Sun–Earth L2 point, approximately 1.5 million kilometers (930,000 mi) from Earth. This location allows it to maintain a stable temperature and a continuous view of its target while keeping the Sun, Earth, and Moon on the same side, blocked by its sunshield.\n*   **Long Lifespan:** While designed for a primary mission of 5.5 years and a planned mission of 10 years, the precision of its launch and initial course corrections saved enough fuel for it to potentially maintain its orbit for around 20 years.\n*   **Complex Deployment:** The telescope underwent a complex, two-week deployment process after launch, including unfolding its solar array, antenna, the massive sunshield, and its segmented primary mirror.\n*   **Micrometeoroid Strikes:** Webb experiences micrometeoroid strikes, averaging once or twice a month. The largest strike, in May 2022, caused noticeable damage but was compensated for using a mirror actuator. Mission personnel have since implemented strategies to avoid pointing the mirror towards 'micrometeoroid avoidance zones.'\n*   **Early Discoveries:** Within weeks of its first images in July 2022, Webb began identifying high-redshift and very luminous galaxies dating from as early as 235 million years after the Big Bang, challenging existing models of early galaxy formation. In May 2024, it identified the most distant known galaxy, JADES-GS-z14-0, seen just 290 million years after the Big Bang.\n*   **International Collaboration:** The JWST is a collaboration between NASA, the European Space Agency (ESA), and the Canadian Space Agency (CSA), with thousands of scientists, engineers, and technicians from 15 countries contributing to its development." # rubocop:disable Layout/LineLength
        expect(agent.final_answer).to eq(final_answer)

        jwst_page_content = File.read("spec/fixtures/files/jwst_page_content.md")

        expect(agent.conversation_history).to eq([
          { "role" => "user", "content" => "Tell me some interesting facts from the James Webb Space Telescope's Wikipedia page" },
          {
            "provider_tool_call_id" => "tool_wikipedia_search_rbwce0jU7EYMR3L6UAh1",
            "name" => "wikipedia_search",
            "arguments" => { "query" => "James Webb Space Telescope" },
            "type" => "tool_call",
            "assistant_message" => nil
          },
          {
            "type" => "tool_call_result",
            "provider_tool_call_id" => "tool_wikipedia_search_rbwce0jU7EYMR3L6UAh1",
            "result" => {
              "results" => [
                {
                  "title" => "James Webb Space Telescope",
                  "snippet" => "The <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> (JWST) is a <span class=\"searchmatch\">space</span> <span class=\"searchmatch\">telescope</span> designed to conduct infrared astronomy. It is the largest <span class=\"searchmatch\">telescope</span> in <span class=\"searchmatch\">space</span>, and is equipped", # rubocop:disable Layout/LineLength
                  "page_id" => 434221,
                  "url" => "https://en.wikipedia.org/wiki/James_Webb_Space_Telescope"
                },
                {
                  "title" => "Timeline of the James Webb Space Telescope",
                  "snippet" =>
                  "The <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> (JWST) is an international 21st-century <span class=\"searchmatch\">space</span> observatory that was launched on 25 December 2021. It is intended to be the", # rubocop:disable Layout/LineLength
                  "page_id" => 52380879,
                  "url" => "https://en.wikipedia.org/wiki/Timeline_of_the_James_Webb_Space_Telescope"
                },
                {
                  "title" => "James Webb Space Telescope sunshield",
                  "snippet" =>
                  "The <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> (JWST) sunshield is a passive thermal control system deployed post-launch to shield the <span class=\"searchmatch\">telescope</span> and instrumentation from", # rubocop:disable Layout/LineLength
                  "page_id" => 52495051,
                  "url" => "https://en.wikipedia.org/wiki/James_Webb_Space_Telescope_sunshield"
                },
                {
                  "title" => "James E. Webb",
                  "snippet" =>
                  "studies. In 2002, the Next Generation <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> was renamed the <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> as a tribute to <span class=\"searchmatch\">Webb</span>. <span class=\"searchmatch\">Webb</span> was born in 1906 in Tally Ho in", # rubocop:disable Layout/LineLength
                  "page_id" => 525237,
                  "url" => "https://en.wikipedia.org/wiki/James_E._Webb"
                },
                {
                  "title" => "Space telescope",
                  "snippet" =>
                  "and ultraviolet radiation, <span class=\"searchmatch\">telescopes</span> and observatories such as the Chandra X-ray Observatory, the <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span>, the XMM-Newton observatory", # rubocop:disable Layout/LineLength
                  "page_id" => 29006,
                  "url" => "https://en.wikipedia.org/wiki/Space_telescope"
                }
              ]
            }
          },
          {
            "provider_tool_call_id" => "tool_fetch_url_GKGtiWPSbWm49odYOBka",
            "name" => "fetch_url",
            "arguments" => { "url" => "https://en.wikipedia.org/wiki/James_Webb_Space_Telescope" },
            "type" => "tool_call",
            "assistant_message" => nil
          },
          {
            "type" => "tool_call_result",
            "provider_tool_call_id" => "tool_fetch_url_GKGtiWPSbWm49odYOBka",
            "result" =>
            {
              "status" => 200,
              "content" => jwst_page_content
            }
          },
          {
            "role" => "assistant",
            "content" =>
            "The James Webb Space Telescope (JWST) is a space telescope designed for infrared astronomy, making it the largest telescope in space. It's equipped with high-resolution and high-sensitivity instruments, allowing it to observe objects too old, distant, or faint for the Hubble Space Telescope.\n\nHere are some interesting facts about the JWST:\n\n*   **Infrared Focus:** Unlike Hubble, which observes in visible and ultraviolet light, Webb primarily observes in the infrared spectrum (0.6–28.5 μm). This allows it to see through cosmic dust and gas, observe colder objects like planets, and study the very early universe, as light from distant objects is redshifted into the infrared.\n*   **Massive Mirror:** Webb's primary mirror is 6.5 meters (21 ft) in diameter, composed of 18 hexagonal, gold-plated beryllium segments. This gives it a collecting area of about 25 square meters (270 sq ft), which is six times larger than Hubble's.\n*   **Extreme Cold:** To observe faint infrared light without interference from its own heat, the telescope must be kept extremely cold, below 50 K (−223 °C; −370 °F). A five-layer sunshield protects it from warming by the Sun, Earth, and Moon.\n*   **Distant Orbit:** Webb operates in a halo orbit around the Sun–Earth L2 point, approximately 1.5 million kilometers (930,000 mi) from Earth. This location allows it to maintain a stable temperature and a continuous view of its target while keeping the Sun, Earth, and Moon on the same side, blocked by its sunshield.\n*   **Long Lifespan:** While designed for a primary mission of 5.5 years and a planned mission of 10 years, the precision of its launch and initial course corrections saved enough fuel for it to potentially maintain its orbit for around 20 years.\n*   **Complex Deployment:** The telescope underwent a complex, two-week deployment process after launch, including unfolding its solar array, antenna, the massive sunshield, and its segmented primary mirror.\n*   **Micrometeoroid Strikes:** Webb experiences micrometeoroid strikes, averaging once or twice a month. The largest strike, in May 2022, caused noticeable damage but was compensated for using a mirror actuator. Mission personnel have since implemented strategies to avoid pointing the mirror towards \"micrometeoroid avoidance zones.\"\n*   **Early Discoveries:** Within weeks of its first images in July 2022, Webb began identifying high-redshift and very luminous galaxies dating from as early as 235 million years after the Big Bang, challenging existing models of early galaxy formation. In May 2024, it identified the most distant known galaxy, JADES-GS-z14-0, seen just 290 million years after the Big Bang.\n*   **International Collaboration:** The JWST is a collaboration between NASA, the European Space Agency (ESA), and the Canadian Space Agency (CSA), with thousands of scientists, engineers, and technicians from 15 countries contributing to its development." # rubocop:disable Layout/LineLength
          },
          {
            "role" => "user",
            "content" =>
            "Error: Previous message contained no tool call. Make a tool call at each step. Available tools: wikipedia_search, fetch_url, agent_final_answer" # rubocop:disable Layout/LineLength
          },
          {
            "provider_tool_call_id" => "tool_agent_final_answer_wAaY7MskySoCpOTI1aG4",
            "name" => "agent_final_answer",
            "arguments" => {
              "final_answer" => final_answer
            },
            "type" => "tool_call",
            "assistant_message" => nil
          }
        ])

        expect(agent.raif_model_tool_invocations.length).to eq(3)
        mti = agent.raif_model_tool_invocations.oldest_first.first
        expect(mti.tool_name).to eq("wikipedia_search")
        expect(mti.tool_type).to eq("Raif::ModelTools::WikipediaSearch")
        expect(mti.tool_arguments).to eq({ "query" => "James Webb Space Telescope" })

        expect(mti.result).to eq({
          "results" => [
            {
              "url" => "https://en.wikipedia.org/wiki/James_Webb_Space_Telescope",
              "title" => "James Webb Space Telescope",
              "page_id" => 434221,
              "snippet" => "The <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> (JWST) is a <span class=\"searchmatch\">space</span> <span class=\"searchmatch\">telescope</span> designed to conduct infrared astronomy. It is the largest <span class=\"searchmatch\">telescope</span> in <span class=\"searchmatch\">space</span>, and is equipped" # rubocop:disable Layout/LineLength
            },
            {
              "url" => "https://en.wikipedia.org/wiki/Timeline_of_the_James_Webb_Space_Telescope",
              "title" => "Timeline of the James Webb Space Telescope",
              "page_id" => 52380879,
              "snippet" => "The <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> (JWST) is an international 21st-century <span class=\"searchmatch\">space</span> observatory that was launched on 25 December 2021. It is intended to be the" # rubocop:disable Layout/LineLength
            },
            {
              "url" => "https://en.wikipedia.org/wiki/James_Webb_Space_Telescope_sunshield",
              "title" => "James Webb Space Telescope sunshield",
              "page_id" => 52495051,
              "snippet" => "The <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> (JWST) sunshield is a passive thermal control system deployed post-launch to shield the <span class=\"searchmatch\">telescope</span> and instrumentation from" # rubocop:disable Layout/LineLength
            },
            {
              "url" => "https://en.wikipedia.org/wiki/James_E._Webb",
              "title" => "James E. Webb",
              "page_id" => 525237,
              "snippet" => "studies. In 2002, the Next Generation <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> was renamed the <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> as a tribute to <span class=\"searchmatch\">Webb</span>. <span class=\"searchmatch\">Webb</span> was born in 1906 in Tally Ho in" # rubocop:disable Layout/LineLength
            },
            {
              "url" => "https://en.wikipedia.org/wiki/Space_telescope",
              "title" => "Space telescope",
              "page_id" => 29006,
              "snippet" => "and ultraviolet radiation, <span class=\"searchmatch\">telescopes</span> and observatories such as the Chandra X-ray Observatory, the <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span>, the XMM-Newton observatory" # rubocop:disable Layout/LineLength
            }
          ]
        })

        mti2 = agent.raif_model_tool_invocations.oldest_first.second
        expect(mti2.tool_name).to eq("fetch_url")
        expect(mti2.tool_type).to eq("Raif::ModelTools::FetchUrl")
        expect(mti2.tool_arguments).to eq({ "url" => "https://en.wikipedia.org/wiki/James_Webb_Space_Telescope" })
        expect(mti2.result).to eq({ "status" => 200, "content" => jwst_page_content })

        mti3 = agent.raif_model_tool_invocations.oldest_first.last
        expect(mti3.tool_name).to eq("agent_final_answer")
        expect(mti3.tool_type).to eq("Raif::ModelTools::AgentFinalAnswer")
        expect(mti3.tool_arguments).to eq({ "final_answer" => final_answer })
        expect(mti3.result).to eq(final_answer)
      end
    end
  end
end
