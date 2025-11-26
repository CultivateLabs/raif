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

    context "with OpenAI Responses" do
      let(:task) { "Tell me some interesting facts from the James Webb Space Telescope's Wikipedia page" }
      let(:llm_model_key) { "open_ai_responses_gpt_4_1_mini" }

      it "processes multiple iterations until finding an answer",
        vcr: { cassette_name: "native_tool_calling_agent/open_ai_responses" } do
        expect(agent.started_at).to be_nil
        expect(agent.completed_at).to be_nil
        expect(agent.failed_at).to be_nil

        agent.run!

        expect(agent.started_at).to be_present
        expect(agent.completed_at).to be_present
        expect(agent.failed_at).to be_nil

        final_answer = "Here are some interesting facts about the James Webb Space Telescope (JWST) from its Wikipedia page:\n\n1. JWST is the largest space telescope ever launched, designed primarily for infrared astronomy, enabling it to see objects too old, distant, or faint for previous telescopes like Hubble.\n\n2. It has a 6.5-meter diameter primary mirror made of 18 hexagonal segments, about 2.7 times larger than Hubble's mirror, providing about six times the collecting area.\n\n3. JWST observes primarily in the infrared spectrum (0.6 to 28.5 micrometers), which allows it to see through cosmic dust and detect cooler objects like planets and distant galaxies.\n\n4. The telescope operates at extremely cold temperatures below 50 K (-223°C) to prevent infrared radiation from the telescope itself from interfering with observations. It uses a large five-layer sunshield to block heat from the Sun, Earth, and Moon.\n\n5. JWST was launched on December 25, 2021, on an Ariane 5 rocket from French Guiana and is positioned near the Sun-Earth L2 point, about 1.5 million kilometers from Earth.\n\n6. The telescope's sunshield is roughly the size of a tennis court when deployed and has a sun protection factor (SPF) of 1,000,000.\n\n7. JWST's mission goals include observing the first stars and galaxies formed after the Big Bang, studying exoplanet atmospheres, and exploring planetary systems and the origins of life.\n\n8. JWST's instruments include the Near Infrared Camera (NIRCam), Near Infrared Spectrograph (NIRSpec), Mid-Infrared Instrument (MIRI), and Fine Guidance Sensor (FGS) with a Near Infrared Imager and Slitless Spectrograph (NIRISS).\n\n9. The telescope underwent a complex deployment and mirror alignment process after launch, with its mirrors being aligned to an accuracy of 50 nanometers.\n\n10. Early scientific results include imaging very distant galaxies from just a few hundred million years after the Big Bang, detecting water in exoplanet atmospheres, and observing star-forming regions and distant galaxy clusters.\n\n11. JWST's total project cost was about $10 billion, with international collaboration involving NASA, ESA, and the Canadian Space Agency.\n\nThese facts highlight JWST's advanced technology, ambitious scientific goals, and its significant role in expanding our understanding of the universe." # rubocop:disable Layout/LineLength
        expect(agent.final_answer).to eq(final_answer)

        jwst_page_content = File.read("spec/fixtures/files/jwst_page_content.md")

        expect(agent.conversation_history).to eq([
          {
            "role" => "user",
            "content" => "Tell me some interesting facts from the James Webb Space Telescope's Wikipedia page"
          },
          {
            "provider_tool_call_id" => "call_abc123",
            "name" => "wikipedia_search",
            "arguments" => { "query" => "James Webb Space Telescope" },
            "type" => "tool_call",
            "assistant_message" => nil
          },
          {
            "type" => "tool_call_result",
            "provider_tool_call_id" => "call_abc123",
            "result" => {
              "results" => [
                {
                  "title" => "James Webb Space Telescope",
                  "snippet" => "The <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> (JWST) is a <span class=\"searchmatch\">space</span> <span class=\"searchmatch\">telescope</span> designed to conduct infrared astronomy. It is the largest <span class=\"searchmatch\">telescope</span> in <span class=\"searchmatch\">space</span>, and is equipped",
                  "page_id" => 434221,
                  "url" => "https://en.wikipedia.org/wiki/James_Webb_Space_Telescope"
                },
                {
                  "title" => "Timeline of the James Webb Space Telescope",
                  "snippet" => "The <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> (JWST) is an international 21st-century <span class=\"searchmatch\">space</span> observatory that was launched on 25 December 2021. It is intended to be the",
                  "page_id" => 52380879,
                  "url" => "https://en.wikipedia.org/wiki/Timeline_of_the_James_Webb_Space_Telescope"
                },
                {
                  "title" => "James Webb Space Telescope sunshield",
                  "snippet" => "The <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> (JWST) sunshield is a passive thermal control system deployed post-launch to shield the <span class=\"searchmatch\">telescope</span> and instrumentation from",
                  "page_id" => 52495051,
                  "url" => "https://en.wikipedia.org/wiki/James_Webb_Space_Telescope_sunshield"
                },
                {
                  "title" => "Space telescope",
                  "snippet" =>
                  "A <span class=\"searchmatch\">space</span> <span class=\"searchmatch\">telescope</span> (also known as <span class=\"searchmatch\">space</span> observatory) is a <span class=\"searchmatch\">telescope</span> in outer <span class=\"searchmatch\">space</span> used to observe astronomical objects. Suggested by Lyman Spitzer in",
                  "page_id" => 29006,
                  "url" => "https://en.wikipedia.org/wiki/Space_telescope"
                },
                {
                  "title" => "James E. Webb",
                  "snippet" =>
                  "studies. In 2002, the Next Generation <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> was renamed the <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> as a tribute to <span class=\"searchmatch\">Webb</span>. <span class=\"searchmatch\">Webb</span> was born in 1906 in Tally Ho in",
                  "page_id" => 525237,
                  "url" => "https://en.wikipedia.org/wiki/James_E._Webb"
                }
              ]
            }
          },
          {
            "provider_tool_call_id" => "call_abc123",
            "name" => "fetch_url",
            "arguments" => { "url" => "https://en.wikipedia.org/wiki/James_Webb_Space_Telescope" },
            "type" => "tool_call",
            "assistant_message" => nil
          },
          {
            "type" => "tool_call_result",
            "provider_tool_call_id" => "call_abc123",
            "result" => {
              "status" => 200,
              "content" => jwst_page_content
            }
          },
          {
            "provider_tool_call_id" => "call_abc123",
            "name" => "agent_final_answer",
            "arguments" => {
              "final_answer" => "Here are some interesting facts about the James Webb Space Telescope (JWST) from its Wikipedia page:\n\n1. JWST is the largest space telescope ever launched, designed primarily for infrared astronomy, enabling it to see objects too old, distant, or faint for previous telescopes like Hubble.\n\n2. It has a 6.5-meter diameter primary mirror made of 18 hexagonal segments, about 2.7 times larger than Hubble's mirror, providing about six times the collecting area.\n\n3. JWST observes primarily in the infrared spectrum (0.6 to 28.5 micrometers), which allows it to see through cosmic dust and detect cooler objects like planets and distant galaxies.\n\n4. The telescope operates at extremely cold temperatures below 50 K (-223°C) to prevent infrared radiation from the telescope itself from interfering with observations. It uses a large five-layer sunshield to block heat from the Sun, Earth, and Moon.\n\n5. JWST was launched on December 25, 2021, on an Ariane 5 rocket from French Guiana and is positioned near the Sun-Earth L2 point, about 1.5 million kilometers from Earth.\n\n6. The telescope's sunshield is roughly the size of a tennis court when deployed and has a sun protection factor (SPF) of 1,000,000.\n\n7. JWST's mission goals include observing the first stars and galaxies formed after the Big Bang, studying exoplanet atmospheres, and exploring planetary systems and the origins of life.\n\n8. JWST's instruments include the Near Infrared Camera (NIRCam), Near Infrared Spectrograph (NIRSpec), Mid-Infrared Instrument (MIRI), and Fine Guidance Sensor (FGS) with a Near Infrared Imager and Slitless Spectrograph (NIRISS).\n\n9. The telescope underwent a complex deployment and mirror alignment process after launch, with its mirrors being aligned to an accuracy of 50 nanometers.\n\n10. Early scientific results include imaging very distant galaxies from just a few hundred million years after the Big Bang, detecting water in exoplanet atmospheres, and observing star-forming regions and distant galaxy clusters.\n\n11. JWST's total project cost was about $10 billion, with international collaboration involving NASA, ESA, and the Canadian Space Agency.\n\nThese facts highlight JWST's advanced technology, ambitious scientific goals, and its significant role in expanding our understanding of the universe."
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
              "snippet" => "The <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> (JWST) is a <span class=\"searchmatch\">space</span> <span class=\"searchmatch\">telescope</span> designed to conduct infrared astronomy. It is the largest <span class=\"searchmatch\">telescope</span> in <span class=\"searchmatch\">space</span>, and is equipped"
            },
            {
              "url" => "https://en.wikipedia.org/wiki/Timeline_of_the_James_Webb_Space_Telescope",
              "title" => "Timeline of the James Webb Space Telescope",
              "page_id" => 52380879,
              "snippet" => "The <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> (JWST) is an international 21st-century <span class=\"searchmatch\">space</span> observatory that was launched on 25 December 2021. It is intended to be the"
            },
            {
              "url" => "https://en.wikipedia.org/wiki/James_Webb_Space_Telescope_sunshield",
              "title" => "James Webb Space Telescope sunshield",
              "page_id" => 52495051,
              "snippet" => "The <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> (JWST) sunshield is a passive thermal control system deployed post-launch to shield the <span class=\"searchmatch\">telescope</span> and instrumentation from"
            },
            {
              "url" => "https://en.wikipedia.org/wiki/Space_telescope",
              "title" => "Space telescope",
              "page_id" => 29006,
              "snippet" => "A <span class=\"searchmatch\">space</span> <span class=\"searchmatch\">telescope</span> (also known as <span class=\"searchmatch\">space</span> observatory) is a <span class=\"searchmatch\">telescope</span> in outer <span class=\"searchmatch\">space</span> used to observe astronomical objects. Suggested by Lyman Spitzer in"
            },
            {
              "url" => "https://en.wikipedia.org/wiki/James_E._Webb",
              "title" => "James E. Webb",
              "page_id" => 525237,
              "snippet" => "studies. In 2002, the Next Generation <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> was renamed the <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> as a tribute to <span class=\"searchmatch\">Webb</span>. <span class=\"searchmatch\">Webb</span> was born in 1906 in Tally Ho in"
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
