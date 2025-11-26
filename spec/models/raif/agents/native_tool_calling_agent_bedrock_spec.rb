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

    context "with Bedrock" do
      let(:task) { "Tell me some interesting facts from the James Webb Space Telescope's Wikipedia page" }
      let(:llm_model_key) { "bedrock_claude_4_5_haiku" }

      before do
        allow(Raif.config).to receive(:llm_api_requests_enabled){ true }
        allow(Raif.config).to receive(:bedrock_models_enabled).and_return(true)

        # To record new VCR cassettes, set real credentials here.
        stubbed_creds = Aws::Credentials.new("placeholder-bedrock-access-key", "placeholder-bedrock-secret-key")
        client = Aws::BedrockRuntime::Client.new(
          region: Raif.config.aws_bedrock_region,
          credentials: stubbed_creds
        )

        allow_any_instance_of(Raif::Llms::Bedrock).to receive(:bedrock_client).and_return(client)
      end

      it "processes multiple iterations until finding an answer",
        vcr: { cassette_name: "native_tool_calling_agent/bedrock", allow_playback_repeats: true } do
        expect(agent.started_at).to be_nil
        expect(agent.completed_at).to be_nil
        expect(agent.failed_at).to be_nil

        agent.run!

        expect(agent.started_at).to be_present
        expect(agent.completed_at).to be_present
        expect(agent.failed_at).to be_nil

        final_answer = "Here are some interesting facts from the James Webb Space Telescope's Wikipedia page:\n\n**Design & Size:**\n- It's the largest telescope in space with a 6.5-meter (21 ft) diameter mirror made of 18 hexagonal gold-coated beryllium segments\n- The mirror is about 2.7 times larger than Hubble's, giving it about 6 times more collecting area\n- It was designed to fold into a rocket that's only 4.57 meters wide to fit during launch\n\n**Temperature & Protection:**\n- Must be kept extremely cold at below 50 K (-223°C / -370°F) to avoid infrared interference\n- Has a five-layer sunshield with an SPF of 1,000,000 (compared to sunscreen's 8-50), each layer as thin as a human hair\n- Located about 1.5 million kilometers from Earth at the Sun-Earth L2 point\n\n**Launch & Cost:**\n- Launched on Christmas Day 2021 (December 25, 2021) on an Ariane 5 rocket\n- Took about 30 days to reach its destination and nearly a month to deploy all its parts\n- Cost just under $10 billion - a dramatic increase from the initial $1 billion estimate in 1998\n- Project suffered massive delays and cost overruns over its 25+ year development\n\n**Capabilities:**\n- Can detect objects up to 100 times fainter than Hubble\n- Can observe the early universe back to about 180 million years after the Big Bang\n- Unlike Hubble, it observes in infrared (0.6-28.5 micrometers) rather than visible light\n- Cannot be serviced in space - unlike Hubble's successful repair missions\n\n**Early Discoveries:**\n- First images released July 12, 2022, revealed galaxies from just 235-290 million years after the Big Bang\n- Discovered GN-z14, a galaxy seen just 290 million years after the Big Bang (as of May 2024)\n- Successfully observed exoplanet atmospheres and detected water vapor around distant planets\n\n**Operational Details:**\n- Uses a modified version of JavaScript for operations\n- Has 132 small actuation motors to position and adjust optics with 10-nanometer accuracy\n- Orbits the Sun in a halo orbit around the L2 point, taking about 6 months to complete\n- Designed to operate for 10 years but may last up to 20 years due to fuel efficiency\n\n**International Collaboration:**\n- A joint project by NASA, ESA (European Space Agency), and CSA (Canadian Space Agency)\n- Over 258 companies, government agencies, and academic institutions from 15 countries participated in construction" # rubocop:disable Layout/LineLength
        expect(agent.final_answer).to eq(final_answer)

        jwst_page_content = File.read("spec/fixtures/files/jwst_page_content.md")

        expect(agent.conversation_history).to eq([
          { "role" => "user", "content" => "Tell me some interesting facts from the James Webb Space Telescope's Wikipedia page" },
          {
            "provider_tool_call_id" => "tooluse_abc123",
            "name" => "wikipedia_search",
            "arguments" => { "query" => "James Webb Space Telescope" },
            "type" => "tool_call",
            "assistant_message" => "I'll search for information about the James Webb Space Telescope on Wikipedia."
          },
          {
            "type" => "tool_call_result",
            "provider_tool_call_id" => "tooluse_abc123",
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
                      "and ultraviolet radiation, <span class=\"searchmatch\">telescopes</span> and observatories such as the Chandra X-ray Observatory, the <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span>, the XMM-Newton observatory",
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
            "provider_tool_call_id" => "tooluse_abc123",
            "name" => "fetch_url",
            "arguments" => { "url" => "https://en.wikipedia.org/wiki/James_Webb_Space_Telescope" },
            "type" => "tool_call",
            "assistant_message" =>
            "Now let me fetch the full Wikipedia page for the James Webb Space Telescope to get more detailed and interesting facts:"
          },
          {
            "type" => "tool_call_result",
            "provider_tool_call_id" => "tooluse_abc123",
            "result" =>
            {
              "status" => 200,
              "content" => jwst_page_content
            }
          },
          {
            "provider_tool_call_id" => "tooluse_abc123",
            "name" => "agent_final_answer",
            "arguments" =>
            {
              "final_answer" =>
                  "Here are some interesting facts from the James Webb Space Telescope's Wikipedia page:\n\n**Design & Size:**\n- It's the largest telescope in space with a 6.5-meter (21 ft) diameter mirror made of 18 hexagonal gold-coated beryllium segments\n- The mirror is about 2.7 times larger than Hubble's, giving it about 6 times more collecting area\n- It was designed to fold into a rocket that's only 4.57 meters wide to fit during launch\n\n**Temperature & Protection:**\n- Must be kept extremely cold at below 50 K (-223°C / -370°F) to avoid infrared interference\n- Has a five-layer sunshield with an SPF of 1,000,000 (compared to sunscreen's 8-50), each layer as thin as a human hair\n- Located about 1.5 million kilometers from Earth at the Sun-Earth L2 point\n\n**Launch & Cost:**\n- Launched on Christmas Day 2021 (December 25, 2021) on an Ariane 5 rocket\n- Took about 30 days to reach its destination and nearly a month to deploy all its parts\n- Cost just under $10 billion - a dramatic increase from the initial $1 billion estimate in 1998\n- Project suffered massive delays and cost overruns over its 25+ year development\n\n**Capabilities:**\n- Can detect objects up to 100 times fainter than Hubble\n- Can observe the early universe back to about 180 million years after the Big Bang\n- Unlike Hubble, it observes in infrared (0.6-28.5 micrometers) rather than visible light\n- Cannot be serviced in space - unlike Hubble's successful repair missions\n\n**Early Discoveries:**\n- First images released July 12, 2022, revealed galaxies from just 235-290 million years after the Big Bang\n- Discovered GN-z14, a galaxy seen just 290 million years after the Big Bang (as of May 2024)\n- Successfully observed exoplanet atmospheres and detected water vapor around distant planets\n\n**Operational Details:**\n- Uses a modified version of JavaScript for operations\n- Has 132 small actuation motors to position and adjust optics with 10-nanometer accuracy\n- Orbits the Sun in a halo orbit around the L2 point, taking about 6 months to complete\n- Designed to operate for 10 years but may last up to 20 years due to fuel efficiency\n\n**International Collaboration:**\n- A joint project by NASA, ESA (European Space Agency), and CSA (Canadian Space Agency)\n- Over 258 companies, government agencies, and academic institutions from 15 countries participated in construction"
            },
            "type" => "tool_call",
            "assistant_message" =>
            "Now I have comprehensive information from the Wikipedia page about the James Webb Space Telescope. Let me compile some interesting facts to share with the user."
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
  end
end
