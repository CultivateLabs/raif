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

        final_answer = "Here are some fascinating facts from the James Webb Space Telescope's Wikipedia page:\n\n**Size & Specifications:**\n- The JWST is the largest telescope in space, with a mirror diameter of 6.5 meters (21 feet)\n- Its primary mirror is made up of 18 hexagonal segments coated with gold-plated beryllium\n- It weighs about 6,500 kg (14,300 lbs) - roughly half the mass of the Hubble Space Telescope\n- Despite having a mirror 2.7 times larger than Hubble's, it observes in the infrared spectrum with longer wavelengths, so it produces images of comparable resolution\n\n**Temperature & Sunshield:**\n- The telescope must be kept below 50 K (−223 °C) to prevent the telescope's own infrared radiation from overwhelming its instruments\n- Its 5-layer sunshield has an effective SPF of 1,000,000 - compared to suntan lotion with SPF 8-50!\n- The sunshield was designed to fold 12 times to fit inside the rocket's cargo bay\n\n**Location:**\n- Webb orbits near the Sun-Earth L2 (Lagrange point 2), approximately 1.5 million kilometers from Earth\n- This is about 4 times farther than the Moon's orbit\n- It operates in a halo orbit around L2, varying between 250,000 to 832,000 km from the point\n\n**Cost & Development:**\n- The project had enormous cost overruns and delays, with a final cost of about $10 billion\n- Originally planned for 2007 with a $1 billion budget, the launch finally occurred December 25, 2021\n- In 2011, Congress nearly cancelled the project but ultimately supported its completion\n\n**Launch & Deployment:**\n- Launched on December 25, 2021 on an Ariane 5 rocket from French Guiana\n- The 344 \"single point failures\" meant 344 tasks had to succeed flawlessly for the telescope to work\n- Deployment took about 13 days, with the sunshield, mirrors, and other components unfolding after launch\n\n**Scientific Capabilities:**\n- It observes wavelengths from 0.6 to 28.5 micrometers (visible red light through mid-infrared)\n- Can detect objects 100 times fainter than Hubble can\n- Can observe galaxies from z≈20 (about 180 million years after the Big Bang)\n- Carries four main scientific instruments: NIRCam, NIRSpec, MIRI, and FGS/NIRISS\n\n**First Results:**\n- Full science operations began July 11, 2022\n- In May 2024, JWST identified the most distant known galaxy, seen just 290 million years after the Big Bang (redshift 14.32)\n- First full-color images revealed remarkably early and luminous galaxies, challenging current models of galaxy formation\n\n**International Collaboration:**\n- A joint project of NASA, ESA (European Space Agency), and CSA (Canadian Space Agency)\n- Over 15 countries and 258 companies, government agencies, and academic institutions participated in its construction\n\nThe telescope is truly a remarkable feat of engineering and international cooperation!" # rubocop:disable Layout/LineLength
        expect(agent.final_answer).to eq(final_answer)

        jwst_page_content = File.read("spec/fixtures/files/jwst_page_content.md")

        expect(agent.conversation_history[4]["result"]["content"]).to eq(jwst_page_content),
          find_string_diff(agent.conversation_history[4]["result"]["content"], jwst_page_content)

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
                      "title" => "Space telescope",
                      "snippet" => "and ultraviolet radiation, <span class=\"searchmatch\">telescopes</span> and observatories such as the Chandra X-ray Observatory, the <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span>, the XMM-Newton observatory", # rubocop:disable Layout/LineLength
                      "page_id" => 29006,
                      "url" => "https://en.wikipedia.org/wiki/Space_telescope"
                    },
                    {
                      "title" => "James Webb Space Telescope sunshield",
                      "snippet" => "The <span class=\"searchmatch\">James</span> <span class=\"searchmatch\">Webb</span> <span class=\"searchmatch\">Space</span> <span class=\"searchmatch\">Telescope</span> (JWST) sunshield is a passive thermal control system deployed post-launch to shield the <span class=\"searchmatch\">telescope</span> and instrumentation from", # rubocop:disable Layout/LineLength
                      "page_id" => 52495051,
                      "url" => "https://en.wikipedia.org/wiki/James_Webb_Space_Telescope_sunshield"
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
            "provider_tool_call_id" => "tooluse_abc123",
            "name" => "fetch_url",
            "arguments" => { "url" => "https://en.wikipedia.org/wiki/James_Webb_Space_Telescope" },
            "type" => "tool_call",
            "assistant_message" => "Now let me fetch the main James Webb Space Telescope Wikipedia page to get more detailed information:"
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
            "arguments" => {
              "final_answer" => "Here are some fascinating facts from the James Webb Space Telescope's Wikipedia page:\n\n**Size & Specifications:**\n- The JWST is the largest telescope in space, with a mirror diameter of 6.5 meters (21 feet)\n- Its primary mirror is made up of 18 hexagonal segments coated with gold-plated beryllium\n- It weighs about 6,500 kg (14,300 lbs) - roughly half the mass of the Hubble Space Telescope\n- Despite having a mirror 2.7 times larger than Hubble's, it observes in the infrared spectrum with longer wavelengths, so it produces images of comparable resolution\n\n**Temperature & Sunshield:**\n- The telescope must be kept below 50 K (−223 °C) to prevent the telescope's own infrared radiation from overwhelming its instruments\n- Its 5-layer sunshield has an effective SPF of 1,000,000 - compared to suntan lotion with SPF 8-50!\n- The sunshield was designed to fold 12 times to fit inside the rocket's cargo bay\n\n**Location:**\n- Webb orbits near the Sun-Earth L2 (Lagrange point 2), approximately 1.5 million kilometers from Earth\n- This is about 4 times farther than the Moon's orbit\n- It operates in a halo orbit around L2, varying between 250,000 to 832,000 km from the point\n\n**Cost & Development:**\n- The project had enormous cost overruns and delays, with a final cost of about $10 billion\n- Originally planned for 2007 with a $1 billion budget, the launch finally occurred December 25, 2021\n- In 2011, Congress nearly cancelled the project but ultimately supported its completion\n\n**Launch & Deployment:**\n- Launched on December 25, 2021 on an Ariane 5 rocket from French Guiana\n- The 344 \"single point failures\" meant 344 tasks had to succeed flawlessly for the telescope to work\n- Deployment took about 13 days, with the sunshield, mirrors, and other components unfolding after launch\n\n**Scientific Capabilities:**\n- It observes wavelengths from 0.6 to 28.5 micrometers (visible red light through mid-infrared)\n- Can detect objects 100 times fainter than Hubble can\n- Can observe galaxies from z≈20 (about 180 million years after the Big Bang)\n- Carries four main scientific instruments: NIRCam, NIRSpec, MIRI, and FGS/NIRISS\n\n**First Results:**\n- Full science operations began July 11, 2022\n- In May 2024, JWST identified the most distant known galaxy, seen just 290 million years after the Big Bang (redshift 14.32)\n- First full-color images revealed remarkably early and luminous galaxies, challenging current models of galaxy formation\n\n**International Collaboration:**\n- A joint project of NASA, ESA (European Space Agency), and CSA (Canadian Space Agency)\n- Over 15 countries and 258 companies, government agencies, and academic institutions participated in its construction\n\nThe telescope is truly a remarkable feat of engineering and international cooperation!" # rubocop:disable Layout/LineLength
            },
            "type" => "tool_call",
            "assistant_message" => "Perfect! I've got the full Wikipedia page on the James Webb Space Telescope. Let me compile some interesting facts from this comprehensive source." # rubocop:disable Layout/LineLength
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
