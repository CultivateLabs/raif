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
        allow(Raif.config).to receive(:open_router_api_key).and_return(ENV["OPEN_ROUTER_API_KEY"])

        expect(agent.started_at).to be_nil
        expect(agent.completed_at).to be_nil
        expect(agent.failed_at).to be_nil

        agent.run!

        expect(agent.started_at).to be_present
        expect(agent.completed_at).to be_present
        expect(agent.failed_at).to be_nil

        final_answer = "The James Webb Space Telescope (JWST) is an infrared-focused space telescope with a 6.5-meter gold-plated beryllium mirror, capable of observing objects 100 times fainter than Hubble and seeing back to 180 million years after the Big Bang. It operates in a halo orbit around the Sun-Earth L2 point to maintain extreme cold temperatures, crucial for its infrared observations. Despite significant cost overruns and delays during its development, its performance has exceeded expectations, delivering groundbreaking images and discoveries, including the most distant known galaxy, JADES-GS-z14-0, observed just 290 million years after the Big Bang. The telescope is a collaborative effort between NASA, ESA, and CSA." # rubocop:disable Layout/LineLength
        expect(agent.final_answer).to eq(final_answer)

        jwst_page_content = File.read("spec/fixtures/files/jwst_page_content.md")

        expect(agent.conversation_history).to eq([
          { "role" => "user", "content" => "Tell me some interesting facts from the James Webb Space Telescope's Wikipedia page" },
          {
            "provider_tool_call_id" => "tool_wikipedia_search_lk1JgPw27IijlFHG4k3y",
            "name" => "wikipedia_search",
            "arguments" => { "query" => "James Webb Space Telescope" },
            "type" => "tool_call",
            "assistant_message" => nil
          },
          {
            "type" => "tool_call_result",
            "provider_tool_call_id" => "tool_wikipedia_search_lk1JgPw27IijlFHG4k3y",
            "result" =>
            {
              "results" => [
                {
                  "title" => "James Webb Space Telescope",
                  "snippet" => "The <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> (JWST) is a <span class=\"searchmatch\">space</span> <span class=\"searchmatch\">telescope</span> designed to conduct infrared astronomy. It is the largest <span class=\"searchmatch\">telescope</span> in <span class=\"searchmatch\">space</span>, and is equipped", # rubocop:disable Layout/LineLength
                  "page_id" => 434221,
                  "url" => "https://en.wikipedia.org/wiki/James_Webb_Space_Telescope"
                },
                {
                  "title" => "Timeline of the James Webb Space Telescope",
                  "snippet" => "The <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> (JWST) is an international 21st-century <span class=\"searchmatch\">space</span> observatory that was launched on 25 December 2021. It is intended to be the", # rubocop:disable Layout/LineLength
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
                  "title" => "Space telescope",
                  "snippet" => "and ultraviolet radiation, <span class=\"searchmatch\">telescopes</span> and observatories such as the Chandra X-ray Observatory, the <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span>, the XMM-Newton observatory", # rubocop:disable Layout/LineLength
                  "page_id" => 29006,
                  "url" => "https://en.wikipedia.org/wiki/Space_telescope"
                },
                {
                  "title" => "James E. Webb",
                  "snippet" => "studies. In 2002, the Next Generation <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> was renamed the <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> as a tribute to <span class=\"searchmatch\">Webb</span>. <span class=\"searchmatch\">Webb</span> was born in 1906 in Tally Ho in", # rubocop:disable Layout/LineLength
                  "page_id" => 525237,
                  "url" => "https://en.wikipedia.org/wiki/James_E._Webb"
                }
              ]
            }
          },
          {
            "provider_tool_call_id" => "tool_fetch_url_Qxcz8ofa9OxZN3XkQMqe",
            "name" => "fetch_url",
            "arguments" => { "url" => "https://en.wikipedia.org/wiki/James_Webb_Space_Telescope" },
            "type" => "tool_call",
            "assistant_message" => nil
          },
          {
            "type" => "tool_call_result",
            "provider_tool_call_id" => "tool_fetch_url_Qxcz8ofa9OxZN3XkQMqe",
            "result" =>
            {
              "status" => 200,
              "content" => jwst_page_content
            }
          },
          {
            "role" => "assistant",
            "content" => "The James Webb Space Telescope (JWST) is the largest telescope in space and is designed to conduct infrared astronomy. Here are some interesting facts from its Wikipedia page:\n\n**Key Features & Capabilities:**\n*   **Infrared Focus:** Unlike the Hubble Space Telescope, which observes in visible and ultraviolet light, Webb primarily observes in the infrared spectrum (0.6–28.5 μm). This allows it to see objects that are too old, distant, or faint for Hubble, as well as penetrate through dust and gas clouds.\n*   **Massive Mirror:** Webb's primary mirror is 6.5 meters (21 feet) in diameter, made of 18 hexagonal, gold-plated beryllium segments. This gives it a collecting area of about 25.4 square meters, six times that of Hubble.\n*   **Extreme Cold:** To effectively observe infrared light, the telescope must be kept extremely cold, below 50 Kelvin (−223 °C; −370 °F). This is achieved through a five-layer sunshield that protects it from the heat of the Sun, Earth, and Moon.\n*   **Distance Vision:** Webb can detect objects up to 100 times fainter than Hubble and observe objects much earlier in the universe's history, back to about 180 million years after the Big Bang. This is crucial for studying the formation of the first stars and galaxies.\n*   **Exoplanet Characterization:** It can gather information on the dimming light of exoplanet transits and even detect methane in their atmospheres, helping to determine if the methane is a biosignature (evidence of life).\n\n**Location & Orbit:**\n*   **L2 Point:** Webb operates in a halo orbit around the Sun-Earth L2 Lagrange point, approximately 1.5 million kilometers (930,000 miles) beyond Earth's orbit. This stable position allows the telescope to maintain a consistent orientation of its sunshield towards the Sun, Earth, and Moon, ensuring continuous power and communication while keeping the instruments cold.\n*   **Fuel Efficiency:** Due to the precision of its launch and initial course corrections, Webb may be able to maintain its orbit for around 20 years, exceeding its initial 10-year design.\n\n**Development & Cost:**\n*   **Long Development:** Initial designs for the telescope began in 1996, with a planned launch in 2007 and a budget of $1 billion. However, the project experienced significant cost overruns and delays, with a total cost of $10 billion and a launch date of December 25, 2021.\n*   **International Collaboration:** The project is a collaboration between NASA, the European Space Agency (ESA), and the Canadian Space Agency (CSA), with thousands of scientists, engineers, and technicians from 15 countries contributing.\n\n**Recent Discoveries & Performance:**\n*   **First Images:** The first full-color images and spectroscopic data were released on July 12, 2022, showcasing stunning views of the universe, including the Carina Nebula, Stephan's Quintet, and the exoplanet WASP-96 b.\n*   **Better Than Expected:** The science performance of JWST has been reported as \"better than expected,\" with instruments capturing highly precise data and tracking moving objects faster than required.\n*   **Early Galaxies:** Within weeks of its first images, Webb identified several high-redshift and very luminous (presumably large) galaxies dating back to as early as 235 million years after the Big Bang, challenging existing models of early galaxy formation. In May 2024, it identified the most distant known galaxy, JADES-GS-z14-0, seen just 290 million years after the Big Bang.\n*   **Micrometeoroid Strikes:** Webb experiences micrometeoroid strikes, with one in May 2022 causing noticeable damage to a mirror segment. However, engineers have implemented strategies to mitigate future risks and the telescope remains fully operational." # rubocop:disable Layout/LineLength
          },
          {
            "role" => "user",
            "content" => "Error: Previous message contained no tool call. Make a tool call at each step. Available tools: wikipedia_search, fetch_url, agent_final_answer" # rubocop:disable Layout/LineLength
          },
          {
            "provider_tool_call_id" => "tool_agent_final_answer_C6mbO64Sz7gEHuuh5eVM",
            "name" => "agent_final_answer",
            "arguments" => {
              "final_answer" => "The James Webb Space Telescope (JWST) is an infrared-focused space telescope with a 6.5-meter gold-plated beryllium mirror, capable of observing objects 100 times fainter than Hubble and seeing back to 180 million years after the Big Bang. It operates in a halo orbit around the Sun-Earth L2 point to maintain extreme cold temperatures, crucial for its infrared observations. Despite significant cost overruns and delays during its development, its performance has exceeded expectations, delivering groundbreaking images and discoveries, including the most distant known galaxy, JADES-GS-z14-0, observed just 290 million years after the Big Bang. The telescope is a collaborative effort between NASA, ESA, and CSA." # rubocop:disable Layout/LineLength
            },
            "type" => "tool_call",
            "assistant_message" => "I apologize for the oversight. I will ensure to make tool calls in each step."
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
              "url" => "https://en.wikipedia.org/wiki/Space_telescope",
              "title" => "Space telescope",
              "page_id" => 29006,
              "snippet" => "and ultraviolet radiation, <span class=\"searchmatch\">telescopes</span> and observatories such as the Chandra X-ray Observatory, the <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span>, the XMM-Newton observatory" # rubocop:disable Layout/LineLength
            },
            {
              "url" => "https://en.wikipedia.org/wiki/James_E._Webb",
              "title" => "James E. Webb",
              "page_id" => 525237,
              "snippet" => "studies. In 2002, the Next Generation <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> was renamed the <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> as a tribute to <span class=\"searchmatch\">Webb</span>. <span class=\"searchmatch\">Webb</span> was born in 1906 in Tally Ho in" # rubocop:disable Layout/LineLength
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
