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
  - `datasets` - For [datasets](#datasets) of eval cases.
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

# Datasets

An eval with one hard-coded input tells you whether your prompt works on that input. [`--repeat`](#repeating-evals) samples the model's non-determinism, but it re-runs the same input every time, so nothing in the results can distinguish "this model is worse" from "this one input happens to be hard for it".

A dataset runs the same eval body over many inputs, and reports a pass rate and a score for each one. Declare it with the `dataset` macro and point an eval at it by name with `dataset:`:

```ruby
class Raif::Evals::Tasks::DocumentSummarizationEvalSet < Raif::Evals::EvalSet
  dataset :documents do
    jsonl("documents.jsonl") # raif_evals/datasets/documents.jsonl
  end

  # setup receives the case, so per-case fixtures are built where fixtures already live
  setup do |eval_case|
    @user = User.create!(email: "test@example.com")
    @document = Document.create!(
      title: eval_case.input["title"],
      content: file(eval_case.input["file"]),
      creator: @user
    )
  end

  eval "produces expected output", dataset: :documents do |eval_case|
    task = Raif::Tasks::DocumentSummarization.run(creator: @user, document: @document)

    expect "task completes successfully" do
      task.completed?
    end

    expect "mentions the document's main subject" do
      task.parsed_response.downcase.include?(eval_case.expected["subject"])
    end

    expect_llm_judge_score(
      task.parsed_response,
      scoring_rubric: Raif::Evals::ScoringRubric.clarity,
      min_passing_score: 4
    )
  end
end
```

With `raif_evals/datasets/documents.jsonl`:

```json
{"id": "climate-report", "input": {"file": "documents/climate_report.html", "title": "2026 Emissions Outlook"}, "expected": {"subject": "emissions"}}
{"id": "earnings-call",  "input": {"file": "documents/earnings_call.html",  "title": "Q2 Earnings Call"},      "expected": {"subject": "revenue"}}
{"id": "press-release",  "input": {"file": "documents/press_release.html",  "title": "Product Launch"},        "expected": {"subject": "launch"}}
```

Both `setup` and the `eval` block accept the case as an optional block argument. Blocks that don't declare one are called as before, so adding a dataset to an eval set never requires touching its other evals.

A case is an input (i.e. a single row in a dataset), not a run. The `eval` block is the procedure; the case is what you feed it. Raif runs the block once per case, times the number of [repeats](#repeating-evals).

Two things to know about how the pieces fit together in one file:

- **Declare a dataset above the evals that use it.** `dataset:` is checked when the class body loads, so a name that has not been declared yet raises there rather than silently running zero cases.
- **`setup` is shared by every eval in the set**, so an eval set that mixes dataset and non-dataset evals hands `setup` a `nil` case for the non-dataset ones.

## Dataset Shape

A dataset is a block that returns an array of cases. The eval will be run against each case in the dataset. Each case is a Hash with up to three keys:

- `id` (**required**) - identifies the case in the console, the results JSON, and [comparisons](#comparing-runs). Ids must be unique within a dataset. A missing or duplicated id raises when the dataset loads, before any LLM call is made, because a case that can't be told apart from another can't be compared against its own past results.
- `input` (**required**) - whatever your `setup` and `eval` blocks need to build the case.
- `expected` (optional) - ground truth to assert against, for cases where you have a known-correct answer.

Inside your blocks, the case is a `Raif::Evals::EvalCase` exposing `id`, `input`, and `expected`. `[]` reads from `input`, so `eval_case["title"]` and `eval_case.input["title"]` are the same thing.

## Dataset Sources

`jsonl` and `json` read from `raif_evals/datasets`:

```ruby
dataset :documents do
  jsonl("documents.jsonl") # one JSON case object per line
end

dataset :short_documents do
  json("short_documents.json") # a JSON array of case objects
end
```

`files` globs `raif_evals/files` and returns matching paths, relative to that directory, so they compose with the existing `file` helper. Use it when a case is a whole file:

```ruby
dataset :corpora do
  files("corpora/*.json").map do |path|
    { id: File.basename(path, ".json"), input: JSON.parse(file(path)) }
  end
end
```

The `dataset` block just has to return an array of case hashes, so a dataset can come from anywhere - a fixture directory, a constant, a query against your own models. Raif imposes no row schema beyond `id`/`input`/`expected`.

## Datasets and Repeats

Datasets and `--repeat` compose: the run is cases &times; repeats independent runs. Each one re-runs `setup` with its own case, inside its own database transaction that is rolled back afterwards, so no case can leak state into another.

An exception raised while running one case is recorded as an error for that case only; the remaining cases still run. That covers `setup` as well as the eval block, so a 20-case dataset does not lose 19 results to one bad fixture.

## Selecting Cases to Run

A full dataset run costs real money. These flags restrict which cases run:

```bash
# Run only the named cases
bundle exec raif evals --cases climate-report,earnings-call

# Run a random 5 cases from each dataset
bundle exec raif evals --sample 5

# Run the same random 5 cases as a previous --sample run
bundle exec raif evals --sample 5 --seed 42
```

Each flag has an environment variable equivalent, alongside the existing `RAIF_EVAL_REPEATS`: `RAIF_EVAL_CASES`, `RAIF_EVAL_SAMPLE`, and `RAIF_EVAL_SEED`.

Sampling without a `--seed` draws different cases each run, which makes two runs uncomparable case-for-case. The same seed and sample size draw the same cases again.

`--cases` filters every dataset in the run, so an id that belongs to one eval set's dataset simply skips the others. If it matches nothing anywhere, the run exits non-zero rather than reporting a suite of zero evals that passed.

## Dataset Results

Each result in the results JSON carries the `case_id` that produced it, alongside the existing `eval_index` and `run_index`. In `summary.eval_pass_rates`, an eval with a dataset reports its overall rate across every case and repeat, plus a `per_case` breakdown:

```json
{
  "eval_set": "Raif::Evals::Tasks::DocumentSummarizationEvalSet",
  "description": "produces expected output",
  "eval_index": 0,
  "cases": 3,
  "repeats": 2,
  "runs": 6,
  "passed": 5,
  "pass_rate": 0.8333,
  "per_case": [
    { "case_id": "climate-report", "runs": 2, "passed": 2, "pass_rate": 1.0 },
    { "case_id": "earnings-call",  "runs": 2, "passed": 2, "pass_rate": 1.0 },
    { "case_id": "press-release",  "runs": 2, "passed": 1, "pass_rate": 0.5 }
  ]
}
```

`runs` is the number of executions counted in the row it appears on: `cases` &times; `repeats` at the top level, and just `repeats` within a `per_case` entry. `run_index` on an individual result identifies which repeat of its case produced it, so it never exceeds `repeats`.

The console output stays compact for dataset evals - one line per case per repeat, since a 20-case dataset at `--repeat 3` would otherwise print several hundred expectation lines. Failing expectations are still printed under the case that failed them:

```
Running Raif::Evals::Tasks::DocumentSummarizationEvalSet
--------------------------------------------------
produces expected output
  ✓ climate-report  run 1  3/3 expectations  clarity 5
  ✓ climate-report  run 2  3/3 expectations  clarity 4
  ✓ earnings-call   run 1  3/3 expectations  clarity 4
  ✓ earnings-call   run 2  3/3 expectations  clarity 5
  ✓ press-release   run 1  3/3 expectations  clarity 4
  ✗ press-release   run 2  2/3 expectations  clarity 3
      ✗ LLM judge score (clarity): >= 4
```

A failing expectation's description is truncated to 100 characters on these lines. An LLM judge expectation is described by its whole criteria, and the same one repeats under every case that failed it, so at full length it buries the case ids and counts the lines exist to show. Pass `label:` to the judge helpers to choose what appears here; the untruncated text is always in the results JSON, the HTML comparison report, and `--verbose` output.

Use `--verbose` (or `Raif.config.evals_verbose_output`) to get the full per-expectation output for every case. An app that turned verbose output on in its initializer gets the compact output back with `--no-verbose`, since a dataset at `--repeat 2` prints several hundred lines of judge reasoning under verbose.

# Running Evals

To run your evals, you can run:

```bash
# Run all eval sets
bundle exec raif evals

# Run a specific eval set file
bundle exec raif evals ./raif_evals/eval_sets/my_eval_set.rb

# Run a specific eval block by line number
bundle exec raif evals ./raif_evals/eval_sets/my_eval_set.rb:23

# Run multiple files
bundle exec raif evals ./raif_evals/eval_sets/file1.rb ./raif_evals/eval_sets/file2.rb:15

# Run each eval 5 times and report a pass rate for each
bundle exec raif evals --repeat 5

# Restrict a dataset run to specific cases, or a random sample of them
bundle exec raif evals --cases climate-report,earnings-call
bundle exec raif evals --sample 5 --seed 42

# Print every expectation for every case rather than one line per case
bundle exec raif evals --verbose

# Force the compact one-line-per-case output, even if your initializer turns verbose on
bundle exec raif evals --no-verbose
```

By default, evals are run against your Rails test environment & database. Each eval is run in a database transaction, which will be rolled back at the end of the eval.

While Raif makes it intentionally difficult to run your normal test suite using real LLM provider API keys, the nature of evals makes it essential that actual API keys are available. When running evals, Raif will load API keys from your initializer, as described in the [setup docs](../getting_started/setup#initial-setup).

Once your evals have run, a JSON file will be created in `raif_evals/results` with the results of each eval. The filename and the file's `configuration` block both record the model the run used, so results from different models can be told apart:

```json
{
  "run_at": "2026-08-02T18:14:22Z",
  "configuration": {
    "default_llm_model_key": "open_ai_responses_gpt_5_6_terra",
    "evals_default_llm_judge_model_key": "anthropic_claude_5_sonnet",
    "repeats": 5,
    "capture_model_completions": "full",
    "sample": null,
    "seed": null
  }
}
```

## Repeating Evals

LLM responses vary between runs, so a single pass/fail per eval cannot separate a real quality difference from one unlucky sample. `--repeat N` (or `RAIF_EVAL_REPEATS=N`) runs each eval N times, re-running `setup` and the eval block for each so the repeats are independent samples rather than a re-scoring of one response.

Repeats sample the model, not your inputs. To vary the input as well, give the eval a [dataset](#datasets) - the two compose, and the run becomes cases &times; repeats.

Each result gains a `run_index` plus an `eval_index` identifying which eval block produced it, and the run's `summary` gains an `eval_pass_rates` array with one row per distinct eval. Rows are keyed on `eval_index` rather than the description, so two eval blocks that happen to share a description still get a rate each:

```json
{
  "eval_set": "MyEvalSet",
  "description": "produces expected output",
  "runs": 5,
  "passed": 4,
  "pass_rate": 0.8
}
```

Pass rates are printed to the console at the end of the run. This is the number to compare when evaluating one model against another.

## Captured LLM Calls

Every LLM call made during an eval is captured and included in the results JSON. Because each eval runs in a transaction that is rolled back, these records are captured before the rollback so they're preserved in the results even though the underlying `Raif::ModelCompletion` rows are not persisted.

For each eval, the results include:
- A `model_completions` array with one entry per LLM call. Each entry captures the `llm_model_key`, `model_api_name`, `system_prompt`, `messages`, the model's `response`, any `response_tool_calls`, token counts (`prompt_tokens`, `completion_tokens`, `total_tokens`, and cache token counts), and cost (`prompt_token_cost`, `output_token_cost`, `total_cost`).
- A `usage` object summarizing the number of LLM calls, total tokens, and total cost for that eval.

```json
{
  "description": "Raif::Tasks::DocumentSummarization produces expected output",
  "passed": true,
  "expectation_results": [ ... ],
  "usage": {
    "model_completions": 1,
    "prompt_tokens": 1200,
    "completion_tokens": 300,
    "total_tokens": 1500,
    "total_cost": 0.0075
  },
  "model_completions": [
    {
      "llm_model_key": "open_ai_gpt_4o",
      "model_api_name": "gpt-4o",
      "system_prompt": "...",
      "messages": [ ... ],
      "response": "...",
      "prompt_tokens": 1200,
      "completion_tokens": 300,
      "total_tokens": 1500,
      "total_cost": 0.0075
    }
  ]
}
```

The run's top-level `summary` also aggregates totals across every eval: `total_model_completions`, `total_prompt_tokens`, `total_completion_tokens`, `total_tokens`, and `total_cost`. These totals are also printed to the console at the end of the run under an `LLM Usage` heading.

> Note: LLM calls made by [LLM judges](#llm-as-judge-expectations) run within the eval and are captured and counted in these totals alongside the calls made by the code under test.

### Limiting What Is Captured

Full capture includes every prompt, message, and response, which for a [dataset](#datasets) run can produce a results file of tens of megabytes. Set the capture mode in your initializer:

```ruby
Raif.configure do |config|
  # :full (default) - prompts, messages, and responses, plus tokens and cost
  # :summary        - tokens and cost only
  # :none           - omit the model_completions array entirely
  config.evals_capture_model_completions = :summary
end
```

The per-eval `usage` object and the run's `summary` totals are the same under all three modes; only the per-call prompt and response text is dropped. The effective mode is recorded in the results `configuration` block, so a later reader can tell a deliberately trimmed capture from a run that made no LLM calls at all.

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

Metadata holds context that isn't a measurement - a judge's reasoning, a case label, the model's raw response. It is stored but never aggregated or compared; [scores](#scores) are the mechanism for numbers that are.

# Scores

`expect` answers yes or no. `score` records a number.

Once two models both clear every pass/fail bar, their results are identical. Scores keep the underlying number, so a drop from 4.6 to 4.1 is visible where "passed" to "passed" is not.

```ruby
eval "produces a usable summary" do
  task = Raif::Tasks::DocumentSummarization.run(creator: @user, document: @document)

  # Observational: recorded in the results, never affects pass/fail
  score "summary_word_count", task.parsed_response.split.length

  # Gated: recorded AND checked, exactly like an expect block
  score "clarity", judge.judgment_score, scale: 1..5, min: 4

  # For metrics where a smaller number is the better one, gated with a ceiling
  score "elapsed_ms", elapsed_ms, max: 5000, higher_is_better: false

  # Both bounds, for a metric that can be wrong in either direction
  score "bullet_count", task.parsed_response.scan("<li>").length, min: 3, max: 7
end
```

- **Without `min:` or `max:`**, a score is recorded and reported but never fails an eval. Word counts, compression ratios, latency, and cost per call are all scoreable this way.
- **With `min:` and/or `max:`**, the score also emits a pass/fail expectation named after the comparison it performs (`clarity score >= 4`, `elapsed_ms score <= 5000`, `bullet_count score >= 3 and <= 7`), so gating behaves the same as an `expect` block and the eval's `passed?` still means what it always meant.
- `scale:` and `higher_is_better:` (default `true`) are recorded with the value so that [`evals:compare`](#comparing-runs) can tell an improvement from a regression. They are independent of the gate: `higher_is_better` says which direction is good, `min:`/`max:` say where the eval starts failing.
- **The name is the metric**, and recording the same one twice for a single eval raises. The summary aggregates by name, so two of them would be averaged into one row, where a regression in one can be masked by an improvement in the other. Values drawn from a single response would also be counted as independent samples, which narrows the confidence interval on correlated data. To score several things on one metric, combine the values and record one score.

Each eval result gains a `scores` array:

```json
"scores": [
  { "name": "clarity", "value": 4.0, "scale": "1..5", "higher_is_better": true, "min": 4, "passed": true },
  { "name": "elapsed_ms", "value": 4210.0, "higher_is_better": false, "max": 5000, "passed": true },
  { "name": "summary_word_count", "value": 284.0, "higher_is_better": true }
]
```

And the run's `summary` gains a `score_summaries` array, with one row per score name per eval. This is what you compare between two models or two prompts:

```json
{
  "eval_set": "Raif::Evals::Tasks::DocumentSummarizationEvalSet",
  "description": "produces expected output",
  "eval_index": 0,
  "name": "clarity",
  "scale": "1..5",
  "higher_is_better": true,
  "n": 6,
  "mean": 4.33,
  "median": 4.5,
  "stddev": 0.47,
  "min": 4.0,
  "max": 5.0,
  "ci95": [4.0, 4.67],
  "per_case": [
    { "case_id": "climate-report", "n": 2, "mean": 4.5 },
    { "case_id": "earnings-call",  "n": 2, "mean": 4.5 },
    { "case_id": "press-release",  "n": 2, "mean": 4.0 }
  ]
}
```

`per_case` is present only for a [dataset](#datasets) eval, since without cases there is nothing to break the mean down by. `ci95` is a 95% bootstrap confidence interval over cases, resampled from a fixed seed so the same numbers always produce the same interval. It and `stddev` are reported alongside the mean because two models a tenth of a point apart with a standard deviation of half a point have not been distinguished.

Both are omitted when there is only one observation to compute them from - a single-case run at `--repeat 1`, for instance. A standard deviation of `0.0` and a zero-width interval are what the arithmetic returns for one value, and in a summary read to decide whether a difference is real they would claim a spread had been measured when none was.

> Note: [`expect_llm_judge_score`](#scored-evaluations) records a score named after its rubric automatically, in addition to its pass/fail expectation. You get both without writing a `score` call yourself.

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

Use `expect_llm_judge_score` to evaluate content against a numerical rubric. As well as the pass/fail expectation, the judge's score is recorded as a [score](#scores) named after the rubric, so it is aggregated into the run summary and can be compared across runs:

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

The score is named after the rubric. [Scores](#scores) are keyed by name, so two `clarity` scores in one eval raise; `score_name:` overrides the rubric-derived name when one eval judges two things against the same rubric:

```ruby
expect_llm_judge_score(bluf, scoring_rubric: rubric, min_passing_score: 4, score_name: "bluf_clarity")
expect_llm_judge_score(findings, scoring_rubric: rubric, min_passing_score: 4, score_name: "findings_clarity")
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
  config.evals_default_llm_judge_model_key = :anthropic_claude_5_sonnet
end
```

Or you can override the model for a specific judge expectation:

```ruby
expect_llm_judge_passes(
  task.parsed_response,
  criteria: "Appropriate for the target audience",
  additional_context: "The user is a beginner programmer with no Ruby experience",
  llm_judge_model_key: :anthropic_claude_5_sonnet
)
```

## Naming Judge Expectations

A judge expectation's description is derived from its criteria or rubric, which gets unwieldy when the criteria is a paragraph. Pass `label:` to name it explicitly:

```ruby
expect_llm_judge_prefers(
  new_summary,
  over: baseline_summary,
  criteria: "Retains the specific figures, dates, and named entities from the source rather than " \
    "paraphrasing them into generalities, while staying within the same length budget",
  label: "beats the paraphrasing baseline"
)
```

The label becomes the expectation's description, which is also part of how [comparisons](#comparing-runs) match a result to its counterpart in an earlier run. Editing a label reads as the old expectation disappearing and a new one arriving.

## Judge Task Attributes

`Raif::Evals::LlmJudge` inherits from `Raif::Task`. If your app has extended `Raif::Task` with attributes it requires - a non-nullable tenant or account column, for example - then judge tasks need them too, and without them the built-in judge helpers can't be used at all: the judge task's insert fails and takes the surrounding eval's transaction with it.

Define `judge_task_attributes` on the eval set to supply them to every judge it runs:

```ruby
class MyEvalSet < Raif::Evals::EvalSet
  setup do
    @account = Account.create!(name: "Eval Account")
  end

  def judge_task_attributes
    { account_id: @account.id }
  end
end
```

It's called per eval, after `setup`, so it can reference anything `setup` created. An individual expectation can add to or override it with `judge_attributes:`:

```ruby
expect_llm_judge_passes(
  task.parsed_response,
  criteria: "Response is professional and helpful",
  judge_attributes: { account_id: other_account.id }
)
```

## Custom LLM Judges

If you need more control over the judge's prompting and response handling, you can create custom LLM judges by inheriting from `Raif::Evals::LlmJudge`. `Raif::Evals::LlmJudge` inherits from `Raif::Task`, so you define it like other [tasks](tasks)

You can view an example of a custom judge for judging document summaries [here](https://github.com/CultivateLabs/raif/blob/main/lib/raif/evals/llm_judges/summarization.rb).

```ruby
class Raif::Evals::LlmJudges::Summarization < Raif::Evals::LlmJudge
  # the original content to evaluate the summary against
  run_with :original_content

  # the summary to evaluate against the original content
  run_with :summary

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
      You are an impartial expert judge of summary quality. You'll be provided an original piece of content and its summary. Your job is to evaluate the summary against the original content based on the following criteria, and assign a score from 1 to 5 for each (5 = excellent, 1 = very poor):

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

In addition to basic `expect` blocks, you can use `expect_tool_invocation` to ensure the LLM invoked a specific tool in its response (or `expect_no_tool_invocation` to verify it did not).

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


# Comparing Runs

Once you have two result files, `evals:compare` diffs them:

```bash
bundle exec raif evals:compare \
  raif_evals/results/eval_run_20260804_180216_open_ai_responses_gpt_5_4.json \
  raif_evals/results/eval_run_20260805_094122_anthropic_claude_5_sonnet.json
```

The first file is the baseline and the second is the candidate. The two most common uses are comparing two models on the same prompts, and comparing the same model before and after a prompt change.

Results are matched on eval set, `eval_index`, expectation description, and `case_id`. Cases are matched individually because a model can improve on average while getting materially worse on one input, which an average alone does not show.

```
Comparing eval runs

  baseline   open_ai_responses_gpt_5_4   2026-08-04 18:02   2 evals x 3 repeats   4 cases   $1.10   eval_run_..._gpt_5_4.json
  candidate  anthropic_claude_5_sonnet   2026-08-05 09:41   2 evals x 3 repeats   4 cases   $1.64   eval_run_..._claude_5_sonnet.json
  judge      anthropic_claude_5_haiku (both runs)

NEW FAILURES (1)
  DocumentSummarizationEvalSet  produces expected output
    press-release        1.00 -> 0.33
      1.00 -> 0.33  summary is between 100 and 1000 words

FIXED (1)
  DocumentSummarizationEvalSet  handles documents that are too short to summarize
    stub-document        0.33 -> 1.00
      0.33 -> 1.00  returns exactly the text 'Unable to generate summary'

SCORE MOVES (2)
  clarity  4.1111 -> 4.5556  +0.4445  (n=18, sd 0.5137 -> 0.4157)
    climate-report       4.3333 -> 5.0  +0.6667
    earnings-call        4.0 -> 4.6667  +0.6667
    press-release        4.0 -> 4.0  0.0
  summary_word_count  284.0 -> 412.0  +128.0  (n=18, sd 31.2 -> 44.7, not gated)

NOT COMPARABLE (1)
  DocumentSummarizationEvalSet  produces expected output
    quarterly-report     candidate only

SUMMARY
  evals passed          16/18 -> 17/18
  expectations          70/72 -> 71/72
  mean clarity          4.1111 -> 4.5556
  mean summary_word_count 284.0 -> 412.0
  total cost            $1.10 -> $1.64
  1 regression beyond --fail-on-regression 0.25 (exit 1)
```

Options:

```bash
# Exit non-zero when a pass rate or a gated score drops by more than this much.
# Without it, regressions are reported and the command still exits 0.
--fail-on-regression 0.25

# text (default), json, or html. html writes a self-contained file next to the results.
--format html

# Compare runs that used different judge models anyway (see below)
--allow-judge-mismatch
```

Some specific behaviors:

- **Cases present in only one run are reported under NOT COMPARABLE, never dropped.** A silently omitted case is indistinguishable from agreement. An expectation that exists on only one side is reported the same way, which is what a renamed description looks like.
- **Runs judged by different models are refused.** Scores from two different judges measure two different things, so the command exits 2 without printing a comparison. `--allow-judge-mismatch` overrides this and labels the output accordingly.
- **Score direction is honored.** A score declared `higher_is_better: false` counts a decrease as an improvement, and ungated observational scores are reported but never trip `--fail-on-regression`.
- **A case that traded one failure for another is a new failure**, even though its pass rate did not move. The expectations that changed are listed under it.
- **No Rails boot.** The command reads two JSON files and does arithmetic, so it does not load your application, need a database, or need an API key.

At `--repeat 1` a single unlucky draw is indistinguishable from a regression. The reported standard deviation indicates how much of a difference is run-to-run variation.

# Setting the LLM for Evals

Raif defaults to using `Raif.config.default_llm_model_key` for LLM API calls. You can override this setting via the `RAIF_DEFAULT_LLM_MODEL_KEY` environment variable.

```bash
RAIF_DEFAULT_LLM_MODEL_KEY=anthropic_claude_5_sonnet bundle exec raif evals
```

# Verbose Output

When debugging failing evals or wanting to see more details about your test runs, you can enable verbose output to see metadata and LLM judge reasoning:

```ruby
# In your initializer
Raif.configure do |config|
  config.evals_verbose_output = true
end
```

Or per run, with `--verbose`:

```bash
bundle exec raif evals --verbose
```

`--no-verbose` (or `RAIF_EVAL_VERBOSE=0`) turns it back off for one run, which is what an app whose initializer sets `evals_verbose_output = true` needs to read a [dataset](#datasets) run: verbose prints every expectation for every case, so a 3-case dataset at `--repeat 2` buries the result in judge reasoning. Passing neither flag leaves the configured value alone.

When enabled, this will display:
- Result metadata for each expectation
- LLM judge reasoning and confidence scores
- Every expectation for every [dataset](#datasets) case, rather than one line per case
- Additional debugging information

This is particularly useful when working with LLM judges to understand why they made certain decisions.

