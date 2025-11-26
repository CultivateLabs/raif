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

  it_behaves_like "an agent"

  it "validates the length of available_model_tools" do
    agent = described_class.new(
      creator: creator,
      task: "What is the capital of France?",
      system_prompt: "System prompt",
    )
    expect(agent).not_to be_valid
    expect(agent.errors[:available_model_tools]).to include("must have at least 1 tool in addition to the agent_final_answer tool")
  end

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

    context "with Anthropic API" do
      let(:task) { "Tell me some interesting facts from the James Webb Space Telescope's Wikipedia page" }
      let(:llm_model_key) { "anthropic_claude_4_5_haiku" }

      it "processes multiple iterations until finding an answer",
        vcr: { cassette_name: "native_tool_calling_agent/anthropic" } do
        allow(Raif.config).to receive(:anthropic_api_key).and_return(ENV["ANTHROPIC_API_KEY"])

        expect(agent.started_at).to be_nil
        expect(agent.completed_at).to be_nil
        expect(agent.failed_at).to be_nil

        agent.run!

        expect(agent.started_at).to be_present
        expect(agent.completed_at).to be_present
        expect(agent.failed_at).to be_nil

        final_answer = "Here are some fascinating facts from the James Webb Space Telescope Wikipedia page:\n\n## Size and Power\n- **JWST is the largest telescope in space** with a 6.5-meter (21-foot) diameter mirror made of 18 hexagonal gold-coated beryllium segments\n- Its mirror is **2.7 times larger than the Hubble Space Telescope**, giving it a collecting area about 6 times greater than Hubble's\n- The telescope weighs about 6,500 kg (14,300 lbs), roughly **half the mass of Hubble**\n\n## Temperature and Protection\n- JWST must be kept **below 50 K (-223°C; -370°F)** to prevent its own infrared radiation from interfering with observations\n- It has a **five-layer sunshield** that's as thin as human hair, with an effective sun protection factor (SPF) of **1,000,000** - compared to sunscreen with SPF 8-50!\n- The sunshield had to be folded **12 times** to fit inside the Ariane 5 rocket\n\n## Location\n- JWST orbits near the **Sun-Earth L2 (Lagrange Point 2)**, approximately **1.5 million kilometers (930,000 miles)** from Earth\n- It's about **4 times farther from Earth than the Moon** (which is ~400,000 km away)\n- It operates in a halo orbit that takes about **6 months** to complete\n\n## Cost and Development\n- The project cost approximately **$10 billion** - it started in 1996 with an estimated budget of just $1 billion\n- The original launch date was planned for **2007**, but faced massive delays and cost overruns\n- **344 single-point failures** were identified - tasks with no alternative means of recovery if unsuccessful\n\n## Scientific Capabilities\n- JWST can detect objects **up to 100 times fainter than Hubble** can\n- It observes wavelengths from **0.6 to 28.5 micrometers** (visible red light through mid-infrared)\n- It can observe objects from **13.1 billion years ago** - viewing the universe as it was shortly after the Big Bang\n\n## Launch and Deployment\n- Launched on **December 25, 2021** on an Ariane 5 rocket from French Guiana\n- The deployment process took about **13 days** with nearly all actions commanded from ground control\n- Reached its destination at L2 on **January 24, 2022**\n- Began full scientific operations on **July 11, 2022**\n\n## Notable Discoveries\n- Detected **unexpectedly large and luminous early galaxies** that formed just 235-280 million years after the Big Bang\n- Identified the **most distant known galaxy** (GN-z14) seen just 290 million years after the Big Bang in May 2024\n- First images showed water vapor in an exoplanet's atmosphere 1,120 light-years away\n\n## International Collaboration\n- Over **258 companies, government agencies, and academic institutions** from 15 countries participated in the project\n- **142 from the United States, 104 from 12 European countries, and 12 from Canada**\n- Named after **James E. Webb**, NASA administrator from 1961-1968 during the Apollo program\n\n" # rubocop:disable Layout/LineLength
        expect(agent.final_answer).to eq(final_answer)

        jwst_page_content = File.read("spec/fixtures/files/jwst_page_content.md")

        expect(agent.conversation_history).to eq([
          { "role" => "user", "content" => "Tell me some interesting facts from the James Webb Space Telescope's Wikipedia page" },
          {
            "provider_tool_call_id" => "toolu_abc123",
            "name" => "wikipedia_search",
            "arguments" => { "query" => "James Webb Space Telescope" },
            "type" => "tool_call",
            "assistant_message" => "I'll search for the James Webb Space Telescope Wikipedia page and find some interesting facts for you."
          },
          {
            "type" => "tool_call_result",
            "provider_tool_call_id" => "toolu_abc123",
            "result" =>
            {
              "results" =>
                  [
                    {
                      "title" => "James Webb Space Telescope",
                      "snippet" =>
                                                                             "The <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> (JWST) is a <span class=\"searchmatch\">space</span> <span class=\"searchmatch\">telescope</span> designed to conduct infrared astronomy. It is the largest <span class=\"searchmatch\">telescope</span> in <span class=\"searchmatch\">space</span>, and is equipped",
                      "page_id" => 434221,
                      "url" => "https://en.wikipedia.org/wiki/James_Webb_Space_Telescope"
                    },
                    {
                      "title" => "Timeline of the James Webb Space Telescope",
                      "snippet" =>
                      "The <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> (JWST) is an international 21st-century <span class=\"searchmatch\">space</span> observatory that was launched on 25 December 2021. It is intended to be the",
                      "page_id" => 52380879,
                      "url" => "https://en.wikipedia.org/wiki/Timeline_of_the_James_Webb_Space_Telescope"
                    },
                    {
                      "title" => "James Webb Space Telescope sunshield",
                      "snippet" =>
                      "The <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> (JWST) sunshield is a passive thermal control system deployed post-launch to shield the <span class=\"searchmatch\">telescope</span> and instrumentation from",
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
            "provider_tool_call_id" => "toolu_abc123",
            "name" => "fetch_url",
            "arguments" => { "url" => "https://en.wikipedia.org/wiki/James_Webb_Space_Telescope" },
            "type" => "tool_call",
            "assistant_message" => "Now let me fetch the full Wikipedia page for the James Webb Space Telescope:"
          },
          {
            "type" => "tool_call_result",
            "provider_tool_call_id" => "toolu_abc123",
            "result" =>
            {
              "status" => 200,
              "content" => jwst_page_content
            },
          },
          {
            "provider_tool_call_id" => "toolu_abc123",
            "name" => "agent_final_answer",
            "arguments" =>
            {
              "final_answer" =>
                  "Here are some fascinating facts from the James Webb Space Telescope Wikipedia page:\n\n## Size and Power\n- **JWST is the largest telescope in space** with a 6.5-meter (21-foot) diameter mirror made of 18 hexagonal gold-coated beryllium segments\n- Its mirror is **2.7 times larger than the Hubble Space Telescope**, giving it a collecting area about 6 times greater than Hubble's\n- The telescope weighs about 6,500 kg (14,300 lbs), roughly **half the mass of Hubble**\n\n## Temperature and Protection\n- JWST must be kept **below 50 K (-223°C; -370°F)** to prevent its own infrared radiation from interfering with observations\n- It has a **five-layer sunshield** that's as thin as human hair, with an effective sun protection factor (SPF) of **1,000,000** - compared to sunscreen with SPF 8-50!\n- The sunshield had to be folded **12 times** to fit inside the Ariane 5 rocket\n\n## Location\n- JWST orbits near the **Sun-Earth L2 (Lagrange Point 2)**, approximately **1.5 million kilometers (930,000 miles)** from Earth\n- It's about **4 times farther from Earth than the Moon** (which is ~400,000 km away)\n- It operates in a halo orbit that takes about **6 months** to complete\n\n## Cost and Development\n- The project cost approximately **$10 billion** - it started in 1996 with an estimated budget of just $1 billion\n- The original launch date was planned for **2007**, but faced massive delays and cost overruns\n- **344 single-point failures** were identified - tasks with no alternative means of recovery if unsuccessful\n\n## Scientific Capabilities\n- JWST can detect objects **up to 100 times fainter than Hubble** can\n- It observes wavelengths from **0.6 to 28.5 micrometers** (visible red light through mid-infrared)\n- It can observe objects from **13.1 billion years ago** - viewing the universe as it was shortly after the Big Bang\n\n## Launch and Deployment\n- Launched on **December 25, 2021** on an Ariane 5 rocket from French Guiana\n- The deployment process took about **13 days** with nearly all actions commanded from ground control\n- Reached its destination at L2 on **January 24, 2022**\n- Began full scientific operations on **July 11, 2022**\n\n## Notable Discoveries\n- Detected **unexpectedly large and luminous early galaxies** that formed just 235-280 million years after the Big Bang\n- Identified the **most distant known galaxy** (GN-z14) seen just 290 million years after the Big Bang in May 2024\n- First images showed water vapor in an exoplanet's atmosphere 1,120 light-years away\n\n## International Collaboration\n- Over **258 companies, government agencies, and academic institutions** from 15 countries participated in the project\n- **142 from the United States, 104 from 12 European countries, and 12 from Canada**\n- Named after **James E. Webb**, NASA administrator from 1961-1968 during the Apollo program\n\n"
            },
            "type" => "tool_call",
            "assistant_message" =>
            "Perfect! I now have the full Wikipedia page content for the James Webb Space Telescope. Let me extract some interesting facts and compile them for you."
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
                  "snippet" =>
                  "studies. In 2002, the Next Generation <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> was renamed the <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> as a tribute to <span class=\"searchmatch\">Webb</span>. <span class=\"searchmatch\">Webb</span> was born in 1906 in Tally Ho in",
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
              "snippet" =>
                       "The <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> (JWST) is a <span class=\"searchmatch\">space</span> <span class=\"searchmatch\">telescope</span> designed to conduct infrared astronomy. It is the largest <span class=\"searchmatch\">telescope</span> in <span class=\"searchmatch\">space</span>, and is equipped"
            },
            {
              "url" => "https://en.wikipedia.org/wiki/Timeline_of_the_James_Webb_Space_Telescope",
              "title" => "Timeline of the James Webb Space Telescope",
              "page_id" => 52380879,
              "snippet" =>
              "The <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> (JWST) is an international 21st-century <span class=\"searchmatch\">space</span> observatory that was launched on 25 December 2021. It is intended to be the"
            },
            {
              "url" => "https://en.wikipedia.org/wiki/James_Webb_Space_Telescope_sunshield",
              "title" => "James Webb Space Telescope sunshield",
              "page_id" => 52495051,
              "snippet" =>
              "The <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> (JWST) sunshield is a passive thermal control system deployed post-launch to shield the <span class=\"searchmatch\">telescope</span> and instrumentation from"
            },
            {
              "url" => "https://en.wikipedia.org/wiki/Space_telescope",
              "title" => "Space telescope",
              "page_id" => 29006,
              "snippet" =>
              "and ultraviolet radiation, <span class=\"searchmatch\">telescopes</span> and observatories such as the Chandra X-ray Observatory, the <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span>, the XMM-Newton observatory"
            },
            {
              "url" => "https://en.wikipedia.org/wiki/James_E._Webb",
              "title" => "James E. Webb",
              "page_id" => 525237,
              "snippet" =>
              "studies. In 2002, the Next Generation <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> was renamed the <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> as a tribute to <span class=\"searchmatch\">Webb</span>. <span class=\"searchmatch\">Webb</span> was born in 1906 in Tally Ho in"
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

    it "handles a tool call with an unavailable tool" do
      stub_raif_agent(agent) do |_messages, model_completion|
        model_completion.response_tool_calls = [
          {
            "name" => "unavailable_tool",
            "arguments" => { "query" => "capital of France" }
          }
        ]

        "I'll try to use a non-existent tool."
      end
      agent.max_iterations = 1
      agent.run!

      expect(agent.conversation_history).to eq([
        { "role" => "user", "content" => "What is the capital of France?" },
        {
          "name" => "unavailable_tool",
          "arguments" => { "query" => "capital of France" },
          "type" => "tool_call",
          "assistant_message" => "I'll try to use a non-existent tool."
        },
        {
          "role" => "user",
          "content" => "Error: Tool 'unavailable_tool' is not a valid tool. Available tools: wikipedia_search, fetch_url, agent_final_answer"
        }
      ])
    end

    it "handles a tool call with invalid tool arguments" do
      stub_raif_agent(agent) do |_messages, model_completion|
        model_completion.response_tool_calls = [
          {
            "name" => "wikipedia_search",
            "arguments" => { "search_term" => "jingle bells" }
          }
        ]

        "I'll try to use Wikipedia search with wrong arguments."
      end

      agent.max_iterations = 1
      agent.run!

      expect(agent.conversation_history).to eq([
        { "role" => "user", "content" => "What is the capital of France?" },
        {
          "name" => "wikipedia_search",
          "arguments" => { "search_term" => "jingle bells" },
          "type" => "tool_call",
          "assistant_message" => "I'll try to use Wikipedia search with wrong arguments."
        },
        {
          "role" => "user",
          "content" =>
          "Error: Invalid tool arguments for the tool 'wikipedia_search'. Tool arguments schema: {\"type\":\"object\",\"additionalProperties\":false,\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"The query to search Wikipedia for\"}},\"required\":[\"query\"]}" # rubocop:disable Layout/LineLength
        }
      ])
    end

    it "handles an iteration with no tool call" do
      stub_raif_agent(agent) do |_messages, model_completion|
        model_completion.response_tool_calls = nil

        "Maybe I'll just jabber instead of using a tool"
      end

      agent.max_iterations = 1
      agent.run!

      expect(agent.conversation_history).to eq([
        { "role" => "user", "content" => "What is the capital of France?" },
        {
          "role" => "assistant",
          "content" => "Maybe I'll just jabber instead of using a tool"
        },
        {
          "role" => "user",
          "content" => "Error: Previous message contained no tool call. Make a tool call at each step. Available tools: wikipedia_search, fetch_url, agent_final_answer" # rubocop:disable Layout/LineLength
        }
      ])
    end
  end

  describe "#build_system_prompt" do
    let(:task) { "What is the capital of France?" }
    let(:tools) { [Raif::TestModelTool, Raif::ModelTools::WikipediaSearch] }
    let(:agent) { described_class.new(task: task, available_model_tools: tools, creator: creator) }

    it "builds the system prompt" do
      prompt = <<~PROMPT.strip
        You are an AI agent that follows the ReAct (Reasoning + Acting) framework to complete tasks step by step using tool/function calls.

        At each step, you must:
        1. Think about what to do next.
        2. Choose and invoke exactly one tool/function call based on that thought.
        3. Observe the results of the tool/function call.
        4. Use the results to update your thought process.
        5. Repeat steps 1-4 until the task is complete.
        6. Provide a final answer to the user's request.

        For your final answer:
        - You **MUST** use the agent_final_answer tool/function to provide your final answer.
        - Your answer should be comprehensive and directly address the user's request.

        Guidelines
        - Always think step by step
        - Be concise in your reasoning but thorough in your analysis
        - If a tool returns an error, try to understand why and adjust your approach
        - If you're unsure about something, explain your uncertainty, but do not make things up
        - Always provide a final answer that directly addresses the user's request

        Remember: Your goal is to be helpful, accurate, and efficient in solving the user's request.
      PROMPT

      expect(agent.build_system_prompt).to eq(prompt)
    end
  end

  describe "validations" do
    it "validates that the LLM supports native tool use" do
      agent = described_class.new(
        creator: creator,
        task: "test",
        llm_model_key: "raif_test_llm"
      )

      agent.llm.supports_native_tool_use = false

      expect(agent).not_to be_valid
      expect(agent.errors[:base]).to include("Raif::Agent#llm_model_key must use an LLM that supports native tool use")
    end
  end

  describe "final answer tool" do
    it "adds the final answer tool to the available model tools" do
      agent = described_class.create!(
        creator: creator,
        task: "What is the capital of France?",
        available_model_tools: [Raif::ModelTools::WikipediaSearch, Raif::ModelTools::FetchUrl]
      )

      expect(agent.available_model_tools_map["agent_final_answer"]).to eq(Raif::ModelTools::AgentFinalAnswer)
    end

    it "doesn't add a final answer tool to the available model tools one is already defined" do
      custom_tool_class = Class.new(Raif::ModelTool) do
        # Force the tool_name to collide with the built-in final answer tool
        def self.tool_name
          "agent_final_answer"
        end

        # Define minimal required class methods for a model tool
        def self.tool_description
          "Custom final answer tool"
        end

        def self.example_model_invocation
          { "name" => tool_name, "arguments" => { "final_answer" => "Example" } }
        end

        def self.tool_arguments_schema
          {
            "type" => "object",
            "additionalProperties" => false,
            "properties" => { "final_answer" => { "type" => "string" } },
            "required" => ["final_answer"]
          }
        end

        def self.process_invocation(tool_invocation)
          tool_invocation.update!(result: { "final_answer" => tool_invocation.tool_arguments["final_answer"] })
          tool_invocation.result
        end

        def self.observation_for_invocation(tool_invocation)
          tool_invocation.result&.fetch("final_answer", "")
        end
      end

      stub_const("CustomFinalAnswerTool", custom_tool_class)

      custom_agent = described_class.create!(
        creator: creator,
        task: "What is the capital of France?",
        available_model_tools: [Raif::ModelTools::WikipediaSearch, CustomFinalAnswerTool]
      )

      # The custom tool with name "agent_final_answer" should be used, not the built-in one
      expect(custom_agent.available_model_tools_map["agent_final_answer"]).to eq(CustomFinalAnswerTool)

      # Ensure the built-in tool was NOT auto-added
      tool_class_names = custom_agent.available_model_tools.map { |t| t.is_a?(String) ? t : t.name }
      expect(tool_class_names).to_not include("Raif::ModelTools::AgentFinalAnswer")
    end
  end
end
