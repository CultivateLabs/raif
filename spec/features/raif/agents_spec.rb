# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Agent features", type: :feature do
  let(:creator) { FB.create(:raif_test_user) }

  let(:model_response_sequence) do
    [
      "<thought>I need to find the birthdate of Jimmy Buffett. The best way to do this is by searching for his information on Wikipedia.</thought>\n<action>{\"tool\": \"wikipedia_search\", \"arguments\": {\"query\": \"Jimmy Buffett\"}}</action>", # rubocop:disable Layout/LineLength
      "<thought>The first search result is directly related to Jimmy Buffett and likely contains his birthdate. I'll fetch the content from that Wikipedia page to find the information.</thought>", # rubocop:disable Layout/LineLength
      "<action>{\"tool\": \"fetch_url\", \"arguments\": {\"url\": \"https://en.wikipedia.org/wiki/Jimmy_Buffett\"}}</action>",
      "<thought>The fetched Wikipedia page for Jimmy Buffett confirms his birthdate as December 25, 1946.</thought>\n<answer>Jimmy Buffett was born on December 25, 1946.</answer>" # rubocop:disable Layout/LineLength
    ]
  end

  let(:wikipedia_page_content){ File.read("#{Raif::Engine.root}/spec/fixtures/files/wikipedia_page_content.html") }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(creator)

    stub_request(:get, "https://en.wikipedia.org/w/api.php?action=query&format=json&list=search&srlimit=5&srprop=snippet&srsearch=Jimmy%20Buffett")
      .to_return(status: 200, body: "{\"batchcomplete\":\"\",\"continue\":{\"sroffset\":5,\"continue\":\"-||\"},\"query\":{\"searchinfo\":{\"totalhits\":1506},\"search\":[{\"ns\":0,\"title\":\"Jimmy Buffett\",\"pageid\":166768,\"snippet\":\"Wikiquote Official website <span class=\\\"searchmatch\\\">Jimmy</span> <span class=\\\"searchmatch\\\">Buffett</span> at AllMusic <span class=\\\"searchmatch\\\">Jimmy</span> <span class=\\\"searchmatch\\\">Buffett</span> discography at Discogs <span class=\\\"searchmatch\\\">Jimmy</span> <span class=\\\"searchmatch\\\">Buffett</span> at IMDb &quot;<span class=\\\"searchmatch\\\">Jimmy</span> <span class=\\\"searchmatch\\\">Buffett</span>&quot; entry at the Encyclopedia\"},{\"ns\":0,\"title\":\"Jimmy Buffett discography\",\"pageid\":11593393,\"snippet\":\"singer-songwriter <span class=\\\"searchmatch\\\">Jimmy</span> <span class=\\\"searchmatch\\\">Buffett</span> consists of 32 studio albums, 11 compilations albums, 14 live albums, one soundtrack album, and 67 singles. <span class=\\\"searchmatch\\\">Buffett</span> was known\"},{\"ns\":0,\"title\":\"Jimmy Buffett's Margaritaville\",\"pageid\":2342489,\"snippet\":\"<span class=\\\"searchmatch\\\">Jimmy</span> <span class=\\\"searchmatch\\\">Buffett&#039;s</span> Margaritaville is a United States\\u2013based hospitality company that manages and franchises a casual dining American restaurant chain, retail\"},{\"ns\":0,\"title\":\"Volcano (Jimmy Buffett album)\",\"pageid\":13570938,\"snippet\":\"the ninth studio album by American popular music singer-songwriter <span class=\\\"searchmatch\\\">Jimmy</span> <span class=\\\"searchmatch\\\">Buffett</span> and is his 11th overall. It was released on August 1, 1979, as his first\"},{\"ns\":0,\"title\":\"Warren Buffett\",\"pageid\":211518,\"snippet\":\"Warren Edward <span class=\\\"searchmatch\\\">Buffett</span> (/\\u02c8b\\u028cf\\u026at/ BUF-it; born August 30, 1930) is an American investor and philanthropist who currently serves as the chairman and CEO\"}]}}") # rubocop:disable Layout/LineLength

    stub_request(:get, "https://en.wikipedia.org/wiki/Jimmy_Buffett")
      .to_return(status: 200, body: wikipedia_page_content)
  end

  it "runs an agent with tools", js: true do
    i = 0
    stub_raif_agent(Raif::Agent) do |_messages|
      i += 1
      model_response_sequence[i - 1]
    end

    visit agents_path

    fill_in "task", with: "What is Jimmy Buffet's birthday?"
    click_button "Run Agent"

    # The sequence of messages is broadcast to the page:
    expect(page).to have_content("user: What is Jimmy Buffet's birthday?")
    expect(page).to have_content("assistant: <thought>I need to find the birthdate of Jimmy Buffett. The best way to do this is by searching")
    expect(page).to have_content("assistant: <action>{\"tool\": \"wikipedia_search\", \"arguments\": {\"query\": \"Jimmy Buffett\"}}</action>")
    expect(page).to have_content("assistant: <observation>{ \"results\": [ { \"title\": \"Jimmy Buffett\", \"snippet\": \"Wikiquote Official website")
    expect(page).to have_content("assistant: <thought>The first search result is directly related to Jimmy Buffett and likely contains his birthdate. I'll fetch the content from that Wikipedia page to find the information.</thought>") # rubocop:disable Layout/LineLength
    expect(page).to have_content("assistant: <action>{\"tool\": \"fetch_url\", \"arguments\": {\"url\": \"https://en.wikipedia.org/wiki/Jimmy_Buffett\"}}</action>")
    expect(page).to have_content("assistant: <observation>Result Status: 200 Result Content: # Jimmy Buffett From Wikipedia, the free encyc")
    expect(page).to have_content("assistant: <thought>The fetched Wikipedia page for Jimmy Buffett confirms his birthdate as December 25, 1946.</thought>") # rubocop:disable Layout/LineLength
    expect(page).to have_content("assistant: <answer>Jimmy Buffett was born on December 25, 1946.</answer>")

    ai = Raif::Agent.last
    expect(ai.type).to eq("Raif::Agents::ReActAgent")
    expect(ai.task).to eq("What is Jimmy Buffet's birthday?")
    expect(ai.started_at).to be_present
    expect(ai.completed_at).to be_present
    expect(ai.failed_at).to be_nil
    expect(ai.failure_reason).to be_nil
    expect(ai.final_answer).to eq("Jimmy Buffett was born on December 25, 1946.")
    expect(ai.available_model_tools).to eq(["Raif::ModelTools::WikipediaSearch", "Raif::ModelTools::FetchUrl"])
    expect(ai.iteration_count).to eq(4)

    expect(ai.raif_model_tool_invocations.length).to eq(2)
    mti = ai.raif_model_tool_invocations.find_by(tool_type: "Raif::ModelTools::WikipediaSearch")
    expect(mti.tool_name).to eq("wikipedia_search")
    expect(mti.tool_arguments).to eq({ "query" => "Jimmy Buffett" })
    expect(mti.result).to eq({
      "results" => [
        {
          "url" => "https://en.wikipedia.org/wiki/Jimmy_Buffett",
          "title" => "Jimmy Buffett",
          "page_id" => 166768,
          "snippet" => "Wikiquote Official website <span class=\"searchmatch\">Jimmy</span> <span class=\"searchmatch\">Buffett</span> at AllMusic <span class=\"searchmatch\">Jimmy</span> <span class=\"searchmatch\">Buffett</span> discography at Discogs <span class=\"searchmatch\">Jimmy</span> <span class=\"searchmatch\">Buffett</span> at IMDb &quot;<span class=\"searchmatch\">Jimmy</span> <span class=\"searchmatch\">Buffett</span>&quot; entry at the Encyclopedia" # rubocop:disable Layout/LineLength
        },
        {
          "url" => "https://en.wikipedia.org/wiki/Jimmy_Buffett_discography",
          "title" => "Jimmy Buffett discography",
          "page_id" => 11593393,
          "snippet" => "singer-songwriter <span class=\"searchmatch\">Jimmy</span> <span class=\"searchmatch\">Buffett</span> consists of 32 studio albums, 11 compilations albums, 14 live albums, one soundtrack album, and 67 singles. <span class=\"searchmatch\">Buffett</span> was known" # rubocop:disable Layout/LineLength
        },
        {
          "url" => "https://en.wikipedia.org/wiki/Jimmy_Buffett's_Margaritaville",
          "title" => "Jimmy Buffett's Margaritaville",
          "page_id" => 2342489,
          "snippet" => "<span class=\"searchmatch\">Jimmy</span> <span class=\"searchmatch\">Buffett&#039;s</span> Margaritaville is a United States–based hospitality company that manages and franchises a casual dining American restaurant chain, retail" # rubocop:disable Layout/LineLength
        },
        {
          "url" => "https://en.wikipedia.org/wiki/Volcano_(Jimmy_Buffett_album)",
          "title" => "Volcano (Jimmy Buffett album)",
          "page_id" => 13570938,
          "snippet" =>
          "the ninth studio album by American popular music singer-songwriter <span class=\"searchmatch\">Jimmy</span> <span class=\"searchmatch\">Buffett</span> and is his 11th overall. It was released on August 1, 1979, as his first" # rubocop:disable Layout/LineLength
        },
        {
          "url" => "https://en.wikipedia.org/wiki/Warren_Buffett",
          "title" => "Warren Buffett",
          "page_id" => 211518,
          "snippet" =>
          "Warren Edward <span class=\"searchmatch\">Buffett</span> (/ˈbʌfɪt/ BUF-it; born August 30, 1930) is an American investor and philanthropist who currently serves as the chairman and CEO" # rubocop:disable Layout/LineLength
        }
      ]
    })

    mti2 = ai.raif_model_tool_invocations.find_by(tool_type: "Raif::ModelTools::FetchUrl")
    expect(mti2.tool_name).to eq("fetch_url")
    expect(mti2.tool_arguments).to eq({ "url" => "https://en.wikipedia.org/wiki/Jimmy_Buffett" })
    expect(mti2.result["status"]).to eq(200)

    # content was converted to markdown
    expect(mti2.result["content"]).to start_with("# Jimmy Buffett\n\nFrom Wikipedia, the free encyclopedia\n\nAmerican singer-songwriter (1946–2023)")
  end
end
