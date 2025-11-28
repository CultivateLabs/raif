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
        expect(agent.started_at).to be_nil
        expect(agent.completed_at).to be_nil
        expect(agent.failed_at).to be_nil

        agent.run!

        expect(agent.started_at).to be_present
        expect(agent.completed_at).to be_present
        expect(agent.failed_at).to be_nil

        final_answer = "Here are some fascinating facts from the James Webb Space Telescope's Wikipedia page:\n\n## Size and Power\n- **Largest telescope in space**: JWST has a mirror diameter of 6.5 meters (21 feet), which is 2.7 times larger than the Hubble Space Telescope's 2.4-meter mirror\n- The telescope's collecting area is about 6 times larger than Hubble's (25.4 m² vs 4.0 m²)\n- It weighs about half as much as Hubble despite being much larger\n\n## Mirror Design\n- The primary mirror is composed of **18 hexagonal segments** made of gold-coated beryllium, which unfolded after launch\n- Each segment can be adjusted with 10 nanometer accuracy using 132 small actuation motors\n- The gold coating provides excellent infrared reflectivity\n\n## Location and Temperature\n- Orbits at the **Sun-Earth L2 point**, approximately 1.5 million kilometers (930,000 miles) from Earth\n- Must be kept below **50 K (-223°C; -370°F)** to prevent the telescope's own infrared radiation from interfering with observations\n- Features a revolutionary five-layer sunshield with an effective SPF of **1,000,000** (compared to sunscreen's 8-50)\n\n## Launch and Development\n- Launched on **December 25, 2021** on an Ariane 5 rocket\n- Took about 30 days to reach L2, arriving on January 24, 2022\n- Development was enormously challenging: originally estimated at $1 billion in 1998, the final cost reached **~$10 billion**\n- The project faced multiple delays and was even nearly cancelled in 2011\n\n## Scientific Capabilities\n- Can detect objects **100 times fainter** than Hubble\n- Observes primarily in infrared (0.6–28.5 micrometers) rather than visible light\n- Can observe extremely distant, early galaxies back to just a few hundred million years after the Big Bang\n- Began full scientific operations on **July 11, 2022**\n\n## Early Discoveries\n- Within two weeks of its first images, Webb identified galaxies dating from 235-280 million years after the Big Bang\n- In May 2024, identified the most distant known galaxy (GN-z14) seen just 290 million years after the Big Bang\n- Released first full-color images on July 12, 2022, revealing stunning views of star-forming regions, nebulae, and galaxy clusters\n\n## International Collaboration\n- A joint project of NASA, ESA (European Space Agency), and CSA (Canadian Space Agency)\n- Over 258 companies, government agencies, and academic institutions participated in the pre-launch project\n- Scientists and engineers from 15 countries contributed to its development\n\n## Unique Features\n- Not designed to be serviced in space (unlike Hubble), making reliability critical\n- Uses a modified version of JavaScript (Nombas ScriptEase 5.00e) for operations\n- Has experienced micrometeoroid strikes, with one in May 2022 causing the most noticeable damage\n- The telescope can see 40% of the sky from any position, but can view all of the sky over a 6-month period" # rubocop:disable Layout/LineLength
        expect(agent.final_answer).to eq(final_answer)

        jwst_page_content = File.read("spec/fixtures/files/jwst_page_content.md")

        expect(agent.conversation_history).to eq([
          { "role" => "user", "content" => "Tell me some interesting facts from the James Webb Space Telescope's Wikipedia page" },
          {
            "provider_tool_call_id" => "toolu_abc123",
            "name" => "wikipedia_search",
            "arguments" => { "query" => "James Webb Space Telescope" },
            "type" => "tool_call",
            "assistant_message" => "I'll search for information about the James Webb Space Telescope on Wikipedia."
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
            "provider_tool_call_id" => "toolu_abc123",
            "name" => "fetch_url",
            "arguments" => { "url" => "https://en.wikipedia.org/wiki/James_Webb_Space_Telescope" },
            "type" => "tool_call",
            "assistant_message" =>
            "Now let me fetch the full Wikipedia page about the James Webb Space Telescope to get more detailed interesting facts."
          },
          {
            "type" => "tool_call_result",
            "provider_tool_call_id" => "toolu_abc123",
            "result" =>
            {
              "status" => 200,
              "content" => jwst_page_content
            }
          },
          {
            "provider_tool_call_id" => "toolu_abc123",
            "name" => "agent_final_answer",
            "arguments" =>
            { "final_answer" => final_answer },
            "type" => "tool_call",
            "assistant_message" =>
            "Perfect! I now have the full Wikipedia page content. Let me compile some interesting facts from this comprehensive article."
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
                       "The <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> (JWST) is a <span class=\"searchmatch\">space</span> <span class=\"searchmatch\">telescope</span> designed to conduct infrared astronomy. It is the largest <span class=\"searchmatch\">telescope</span> in <span class=\"searchmatch\">space</span>, and is equipped" # rubocop:disable Layout/LineLength
            },
            {
              "url" => "https://en.wikipedia.org/wiki/Timeline_of_the_James_Webb_Space_Telescope",
              "title" => "Timeline of the James Webb Space Telescope",
              "page_id" => 52380879,
              "snippet" =>
              "The <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> (JWST) is an international 21st-century <span class=\"searchmatch\">space</span> observatory that was launched on 25 December 2021. It is intended to be the" # rubocop:disable Layout/LineLength
            },
            {
              "url" => "https://en.wikipedia.org/wiki/James_Webb_Space_Telescope_sunshield",
              "title" => "James Webb Space Telescope sunshield",
              "page_id" => 52495051,
              "snippet" =>
              "The <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> (JWST) sunshield is a passive thermal control system deployed post-launch to shield the <span class=\"searchmatch\">telescope</span> and instrumentation from" # rubocop:disable Layout/LineLength
            },
            {
              "url" => "https://en.wikipedia.org/wiki/James_E._Webb",
              "title" => "James E. Webb",
              "page_id" => 525237,
              "snippet" =>
              "studies. In 2002, the Next Generation <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> was renamed the <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> as a tribute to <span class=\"searchmatch\">Webb</span>. <span class=\"searchmatch\">Webb</span> was born in 1906 in Tally Ho in" # rubocop:disable Layout/LineLength
            },
            {
              "url" => "https://en.wikipedia.org/wiki/Space_telescope",
              "title" => "Space telescope",
              "page_id" => 29006,
              "snippet" =>
              "and ultraviolet radiation, <span class=\"searchmatch\">telescopes</span> and observatories such as the Chandra X-ray Observatory, the <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span>, the XMM-Newton observatory" # rubocop:disable Layout/LineLength
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
