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
  end
end
