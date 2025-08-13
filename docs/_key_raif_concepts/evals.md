---
layout: default
title: Evals
nav_order: 5
description: "Create and run LLM evals to help you iterate, test, and improve your prompts"
---

{% include table-of-contents.md %}

# Evals Setup

Raif includes the ability to create and run LLM evals to help you iterate, test, and improve your LLM interactions/prompts.

Evals are automatically set up when you run the install command during [setup](../getting_started/setup#initial-setup). If you need to set up evals manually, you can run:
```bash
bundle exec raif evals:setup
```

This will:
- Create a `raif_evals` directory in your Rails project with a `setup.rb` file. This file is loaded automatically when you run your evals.
- Within `raif_evals`, it will also create the following directories:
  - `eval_sets` - Where your actual evals will go.
  - `files` - For any files (e.g. a PDF document or HTML page) that you want to use in your evals.
  - `results` - Where the results of your eval runs will be stored.

# Creating an Eval Set

Raif's generators for [tasks](tasks), [conversations](conversations), and [agents](agents) will automatically create a related eval set for you. To create an eval set manually, you can run:

```bash
rails g raif:eval_set MyExample
```

This will create `raif_evals/eval_sets/my_example_eval_set.rb`. Each eval set is made up of:
- A `setup` block that runs before each eval
- A `teardown` block that runs after each eval
- One or more `eval` blocks, each containing:
  - A description of the eval
  - One or more `expect` blocks that return true or false to indicate if the eval passed or failed

The `expect` blocks in a Raif `eval` are similar to expectations/assertions in a normal test suite. But unlike test suite expectations/assertions, a failure in an `expect` block will not terminate the `eval`. Your evals are expected to run against an actual LLM (costing you API bills), so this allows you to test multiple `expect` blocks via a single API call, even if some of them fail.

# Example Eval Set

Below is an example eval set for the `Raif::Tasks::DocumentSummarization` task created in the [tasks docs](tasks#html-response-format-tasks).

```ruby
class Raif::Evals::Tasks::DocumentSummarizationEvalSet < Raif::Evals::EvalSet
  # Setup method runs before each eval
  setup do
    # Assumes your app has a User model
    @user = User.create!(email: "test@example.com")
  end

  eval "Raif::Tasks::DocumentSummarization produces expected output" do
    # Assumes your app has a Document model
    document = Document.create!(
      title: "Example Document",
      content: file("documents/example.html"), # assumes a file exists at raif_evals/files/documents/example.html
      creator: @user
    )

    task = Raif::Tasks::DocumentSummarization.run(
      creator: @user,
      document: document,
    )

    expect "task completes successfully" do
      task.completed?
    end

    summary_word_count = task.parsed_response.length
    expect "summary is between 100 and 1000 words", result_metadata: { word_count: summary_word_count } do
      summary_word_count.between?(100, 1000)
    end

    basic_html_tags = %w[p b i div strong]
    expect "contains basic HTML tags in the output" do
      basic_html_tags.any?{ |tag| task.parsed_response.include?("<#{tag}>") }
    end

    # Use LLM to judge the clarity of the summary
    expect_llm_judge_score(
      task.parsed_response,
      scoring_rubric: Raif::Evals::ScoringRubric.clarity,
      min_passing_score: 4,
      result_metadata: {
        compression_ratio: (document.content.length.to_f / summary_word_count).round(2)
      }
    )
  end

  eval "handles documents that are too short to summarize" do
    # Assumes your app has a Document model
    document = Document.create!(
      title: "Example Document",
      content: "short doc",
      creator: @user
    )

    task = Raif::Tasks::DocumentSummarization.run(
      creator: @user,
      document: document,
    )

    expect "returns exactly the text 'Unable to generate summary'" do
      task.parsed_response == "Unable to generate summary"
    end
  end
end
```

# Running Evals

To run your evals, you can run:

```bash
# Run all eval sets
bundle exec raif evals

# Run a single eval set
bundle exec raif evals Raif::Evals::Tasks::DocumentSummarizationEvalSet
```

By default, evals are run against your Rails test environment & database. Each eval is run in a database transaction, which will be rolled back at the end of the eval.

While Raif makes it intentionally difficult to run your normal test suite using real LLM provider API keys, the nature of evals makes it essential that actual API keys are available. When running evals, Raif will load API keys from your initializer, as described in the [setup docs](../getting_started/setup#initial-setup).

Once your evals have run, a JSON file will be created in `raif_evals/results` with the results of each eval.

## Adding Result Metadata to Expectations

You can attach metadata to any `expect` block to capture additional context that will be stored in the results JSON file. This is useful for tracking scores, metrics, or other relevant information alongside pass/fail results.

```ruby
result_metadata = { 
  overall_score: task.overall_score, 
  word_count: summary.length
}

expect "Summary is high quality", result_metadata: result_metadata do
  task.overall_score >= 4
end
```

The metadata will be included in the results JSON:

```json
{
  "expectation_results": [
    {
      "description": "Summary is high quality",
      "status": "passed",
      "metadata": {
        "overall_score": 5,
        "word_count": 250
      }
    }
  ]
}
```

This is particularly useful when using [LLM judges](#llm-as-judge-expectations) to capture their scores and reasoning alongside your pass/fail criteria.



# LLM-as-Judge Expectations

Raif includes built-in support for using LLMs to evaluate outputs, providing more flexible and nuanced testing than traditional assertions. These "LLM judges" can assess quality, compare outputs, and score responses against rubrics.

## Binary Pass/Fail Judgments

Use `expect_llm_judge_passes` to evaluate whether content meets specific criteria:

```ruby
eval "produces professional output" do
  task = Raif::Tasks::CustomerResponse.run(creator: @user, query: "Fix my broken product!")
  
  expect_llm_judge_passes(
    task.parsed_response,
    criteria: "Response is polite, professional, and addresses the customer's concern"
  )
end
```

You can provide examples to guide the judge & instruct it to apply criteria strictly:

```ruby
expect_llm_judge_passes(
  output,
  criteria: "Contains a proper greeting",
  strict: true,  # Instruct the judge to apply criteria strictly without leniency
  examples: [
    { 
      content: "Hello! How can I help you today?", 
      passes: true, 
      reasoning: "Friendly greeting present" 
    },
    { 
      content: "What do you want?", 
      passes: false, 
      reasoning: "No greeting, unprofessional tone" 
    }
  ]
)
```

## Scored Evaluations

Use `expect_llm_judge_score` to evaluate content against a numerical rubric:

```ruby
eval "produces high-quality technical documentation" do
  task = Raif::Tasks::TechnicalWriter.run(creator: @user, topic: "API authentication")
  
  expect_llm_judge_score(
    task.parsed_response,
    scoring_rubric: Raif::Evals::ScoringRubric.clarity,
    min_passing_score: 4
  )
end
```

### Built-in Scoring Rubrics

Raif includes several built-in rubrics:
- `ScoringRubric.accuracy` - Evaluates factual correctness (1-5)
- `ScoringRubric.helpfulness` - Evaluates how helpful the response is (1-5)
- `ScoringRubric.clarity` - Evaluates ease of understanding (1-5)

See the [scoring rubric source](https://github.com/CultivateLabs/raif/blob/main/lib/raif/evals/scoring_rubric.rb) for details.

### Custom Scoring Rubrics

You can also create custom rubrics:

```ruby
rubric = Raif::Evals::ScoringRubric.new(
  name: :technical_depth,
  description: "Evaluates technical depth and accuracy",
  levels: [
    { score: 5, description: "Expert-level technical detail with perfect accuracy" },
    { score: 4, description: "Strong technical content with minor gaps" },
    { score: 3, description: "Adequate technical coverage" },
    { score: 2, description: "Basic technical content" },
    { score: 1, description: "Minimal technical value" }
  ]
)

expect_llm_judge_score(
  output,
  scoring_rubric: rubric,
  min_passing_score: 4
)
```

Or create rubrics with score ranges:

```ruby
rubric = Raif::Evals::ScoringRubric.new(
  name: :code_quality,
  description: "Evaluates code quality and best practices",
  levels: [
    { score_range: (9..10), description: "Production-ready, follows all best practices" },
    { score_range: (7..8), description: "Good quality, minor improvements possible" },
    { score_range: (5..6), description: "Functional but needs refactoring" },
    { score_range: (3..4), description: "Poor quality, significant issues" },
    { score_range: (0..2), description: "Broken or severely flawed" }
  ]
)

expect_llm_judge_score(
  generated_code,
  scoring_rubric: rubric,
  min_passing_score: 7
)
```

Or you can provide the rubric as a string:

```ruby
rubric = <<~RUBRIC
  - 10 points: Production-ready, follows all best practices
  - 8 points: Good quality, minor improvements possible
  - 6 points: Functional but needs refactoring
  - 4 points: Poor quality, significant issues
  - 2 points: Broken or severely flawed
RUBRIC

expect_llm_judge_score(
  generated_code,
  scoring_rubric: rubric,
  min_passing_score: 7
)
```





## Comparative Judgments

Use `expect_llm_judge_prefers` to compare two outputs and verify one is better. The comparative judge automatically randomizes position (A/B) in the prompt to avoid bias and supports tie detection:

```ruby
eval "new prompt improves over baseline" do
  baseline_response = Raif::Tasks::OldSummarizer.run(creator: @user, document: doc).parsed_response
  improved_response = Raif::Tasks::NewSummarizer.run(creator: @user, document: doc).parsed_response
  
  expect_llm_judge_prefers(
    improved_response,
    over: baseline_response,
    criteria: "More concise while retaining all key information"
  )
end
```

Or if you want to instruct the judge to pick a winner, you can set `allow_ties` to false:
```ruby
eval "new prompt improves over baseline" do
  baseline_response = Raif::Tasks::OldSummarizer.run(creator: @user, document: doc).parsed_response
  improved_response = Raif::Tasks::NewSummarizer.run(creator: @user, document: doc).parsed_response
  
  expect_llm_judge_prefers(
    improved_response,
    over: baseline_response,
    criteria: "More concise while retaining all key information",
    allow_ties: false
  )
end
```

## Additional Context

All judge expectations support providing additional context to help with evaluation:

```ruby
expect_llm_judge_passes(
  task.parsed_response,
  criteria: "Appropriate for the target audience",
  additional_context: "The user is a beginner programmer with no Ruby experience"
)
```

## Adding Result Metadata to Judge Expectations

All LLM judge expectations support adding [result metadata](#adding-result-metadata-to-expectations) that will be merged with the judge's automatic metadata (scores, reasoning, confidence) in the results JSON. Use the `result_metadata` parameter:

```ruby
expect_llm_judge_passes(
  response,
  criteria: "Response is professional and helpful",
  result_metadata: {
    test_case_id: "CS-001",
    scenario: "customer_complaint",
    priority: "high"
  }
)
```

The custom metadata will be combined with the judge's metadata in the results:

```json
{
  "expectation_results": [
    {
      "description": "LLM judge: Response is professional and helpful",
      "status": "passed",
      "metadata": {
        "test_case_id": "CS-001",
        "scenario": "customer_complaint",
        "priority": "high",
        "passes": true,
        "reasoning": "The response demonstrates professionalism...",
        "confidence": 0.92
      }
    }
  ]
}
```

## Configuring the Judge LLM Model

You can configure the LLM model used for judging in your initializer:

```ruby
Raif.configure do |config|
  # Use a specific model for LLM-as-judge
  config.evals_default_llm_judge_model_key = :anthropic_claude_3_5_sonnet
end
```

Or you can override the model for a specific judge expectation:

```ruby
expect_llm_judge_passes(
  task.parsed_response,
  criteria: "Appropriate for the target audience",
  additional_context: "The user is a beginner programmer with no Ruby experience",
  llm_judge_model_key: :anthropic_claude_3_5_sonnet
)
```

## Custom LLM Judges

If you need more control over the judge's prompting and response handling, you can create custom LLM judges by inheriting from `Raif::Evals::LlmJudge`. `Raif::Evals::LlmJudge` inherits from `Raif::Task`, so you define it like other [tasks](tasks)

You can view an example of a custom judge for judging document summaries [here](https://github.com/CultivateLabs/raif/blob/main/lib/raif/evals/llm_judges/summarization.rb).

```ruby
class Raif::Evals::LlmJudges::Summarization < Raif::Evals::LlmJudge
  # the original content to evaluate the summary against
  task_run_arg :original_content

  # the summary to evaluate against the original content
  task_run_arg :summary

  json_response_schema do
    object :coverage do
      string :justification, description: "Justification for the score"
      number :score, description: "Score from 1 to 5", enum: [1, 2, 3, 4, 5]
    end

    object :accuracy do
      string :justification, description: "Justification for the score"
      number :score, description: "Score from 1 to 5", enum: [1, 2, 3, 4, 5]
    end

    object :clarity do
      string :justification, description: "Justification for the score"
      number :score, description: "Score from 1 to 5", enum: [1, 2, 3, 4, 5]
    end

    object :conciseness do
      string :justification, description: "Justification for the score"
      number :score, description: "Score from 1 to 5", enum: [1, 2, 3, 4, 5]
    end

    object :overall do
      string :justification, description: "Justification for the score"
      number :score, description: "Score from 1 to 5", enum: [1, 2, 3, 4, 5]
    end
  end

  def build_system_prompt
    <<~PROMPT.strip
      You are an impartial expert judge of summary quality. You'll be provided a original piece of content and its summary. Your job is to evaluate the summary against the original content based on the following criteria, and assign a score from 1 to 5 for each (5 = excellent, 1 = very poor):

      **Coverage (Relevance & Completeness):** Does the summary capture all the important points of the original content?
      - 5 = Excellent Coverage - Nearly all key points and essential details from the content are present in the summary, with no major omissions.
      - 4 = Good Coverage - Most important points are included, but a minor detail or two might be missing.
      - 3 = Fair Coverage - Some main points appear, but the summary misses or glosses over other important information.
      - 2 = Poor Coverage - Many critical points from the content are missing; the summary is incomplete.
      - 1 = Very Poor - The summary fails to include most of the content's main points (highly incomplete).

      **Accuracy (Faithfulness to the Source):** Is the summary factually correct and free of hallucinations or misrepresentations of the content?
      - 5 = Fully Accurate - All statements in the summary are correct and directly supported by the content. No errors or invented information.
      - 4 = Mostly Accurate - The summary is generally accurate with perhaps one minor error or slight ambiguity, but no significant falsehoods.
      - 3 = Some Inaccuracies - Contains a few errors or unsupported claims from the content, but overall captures the gist correctly.
      - 2 = Mostly Inaccurate - Multiple statements in the summary are incorrect or not supported by the content.
      - 1 = Completely Inaccurate - The summary seriously distorts or contradicts the content; many claims are false or not in the source.

      **Clarity and Coherence:** Is the summary well-written and easy to understand? (Consider organization, flow, and whether it would make sense to a reader.)
      - 5 = Very Clear & Coherent - The summary is logically organized, flows well, and would be easily understood by the target reader. No confusion or ambiguity.
      - 4 = Mostly Clear - Readable and mostly well-structured, though a sentence or transition could be smoother.
      - 3 = Somewhat Clear - The summary makes sense overall but might be disjointed or awkward in places, requiring effort to follow.
      - 2 = Generally Unclear - Lacks coherence or has poor phrasing that makes it hard to follow the ideas.
      - 1 = Very Poor Clarity - The summary is very confusing or poorly structured, making it hard to understand.

      **Conciseness:** Is the summary succinct while still informative? (It should omit unnecessary detail but not at the expense of coverage.)
      - 5 = Highly Concise - The summary is brief yet covers all important information (no fluff or redundancy).
      - 4 = Concise - Generally to-the-point, with only minor redundancy or superfluous content.
      - 3 = Moderately Concise - Some excess detail or repetition that could be trimmed, but not egregious.
      - 2 = Verbose - Contains a lot of unnecessary detail or repeats points, making it longer than needed.
      - 1 = Excessively Verbose - The summary is overly long or wordy, with much content that doesn't add value.
    PROMPT
  end

  def build_prompt
    <<~PROMPT.strip
      # Instructions
      Below is an original piece of content and its summary. Evaluate the summary against the original content based on our 4 criteria. For each, you should provide:
      - A brief justification (1-3 sentences) noting any relevant observations (e.g. what was missing, incorrect, unclear, or well-done).
      - A score from 1 to 5 (5 = excellent, 1 = very poor).

      Finally, provide an **overall evaluation** of the summary, consisting of a brief justification (1-3 sentences) and a score from 1 to 5 (5 = excellent, 1 = very poor).

      # Output Format
      Format your output as a JSON object with the following keys:
      {
        "coverage": {
          "justification": "...",
          "score": 1-5
        },
        "accuracy": {
          "justification": "...",
          "score": 1-5
        },
        "clarity": {
          "justification": "...",
          "score": 1-5
        },
        "conciseness": {
          "justification": "...",
          "score": 1-5
        },
        "overall": {
          "justification": "...",
          "score": 1-5
        }
      }
      #{additional_context_prompt}
      # Original Article/Document
      #{original_content}

      # Summary to Evaluate
      #{summary}
    PROMPT
  end

private

  def additional_context_prompt
    return if additional_context.blank?

    <<~PROMPT
      \n# Additional context:
      #{additional_context}
    PROMPT
  end
end
```

Then use it directly in your eval sets for additional flexibility:

```ruby
eval "Summary meets quality standards" do
  doc = Document.create!(content: "Long article content...")
  summary_task = Raif::Tasks::Summarizer.run(document: doc)
  
  judge_task = Raif::Evals::LlmJudges::Summarization.run(
    original_content: doc.content,
    summary: summary_task.parsed_response["summary"]
  )

  result_metadata = { 
    score: judge_task.parsed_response["overall"]["score"], 
    justification: judge_task.parsed_response["overall"]["justification"] 
  }
  expect "Summary is high quality overall", result_metadata: result_metadata do
    judge_task.parsed_response["overall"]["score"] >= 4
  end

  ["coverage", "accuracy", "clarity", "conciseness"].each do |score_type|
    score = judge_task.parsed_response[score_type]["score"]
    justification = judge_task.parsed_response[score_type]["justification"]

    result_metadata = { 
      score: score, 
      justification: justification 
    }
    expect "#{score_type.capitalize} is >= 4", result_metadata: result_metadata do
      score >= 4
    end
  end
end
```

This approach gives you control over the judge's prompting, response schema, and result processing while still integrating with the eval framework.

# Expecting Tool Calls

In addition to basic `expect` blocks, you can use `expect_tool_invocation` to ensure the LLM invoked a specific tool in its response.

```ruby
eval "invokes the WikipediaSearch tool" do
  user = User.create!(email: "test@example.com")

  conversation = Raif::Conversation.create(
    creator: user,
    tools: ["Raif::ModelTools::WikipediaSearch"]
  )

  conversation_entry = conversation.entries.create!(
    user_message: "What pages does Wikipedia have about the moon?",
    creator: user
  )

  conversation_entry.process_entry!

  expect_tool_invocation(conversation_entry, "Raif::ModelTools::WikipediaSearch", with: { "query" => "moon" })
end
```


# Setting the LLM for Evals

Raif defaults to using `Raif.config.default_llm_model_key` for LLM API calls. You can override this setting via the `RAIF_DEFAULT_LLM_MODEL_KEY` environment variable.

```bash
RAIF_DEFAULT_LLM_MODEL_KEY=anthropic_claude_4_sonnet bundle exec raif evals
```

