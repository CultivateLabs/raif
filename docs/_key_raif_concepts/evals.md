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
  - `results` - Where the [results](#results) of your eval runs will be stored.

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

# Run 8 evals at a time instead of one after another
bundle exec raif evals --concurrency 8

# Print every expectation for every case rather than one line per case
bundle exec raif evals --verbose

# Force the compact one-line-per-case output, even if your initializer turns verbose on
bundle exec raif evals --no-verbose

# Pick up an interrupted run where it stopped, without paying for its results again
bundle exec raif evals --resume raif_evals/results/eval_run_20260805_094122_anthropic_claude_5_sonnet.partial.jsonl
```

`--cases`, `--sample`, and `--seed` only affect evals that have a [dataset](#datasets); see [Selecting Cases to Run](#selecting-cases-to-run).

By default, evals are run against your Rails test environment & database. Each eval is run in a database transaction, which will be rolled back at the end of the eval.

While Raif makes it intentionally difficult to run your normal test suite using real LLM provider API keys, the nature of evals makes it essential that actual API keys are available. When running evals, Raif will load API keys from your initializer, as described in the [setup docs](../getting_started/setup#initial-setup).

## Results

Once your evals have run, a JSON file will be created in `raif_evals/results` with the results of each eval. The filename and the file's `configuration` block both record the model the run used, so results from different models can be told apart:

```json
{
  "run_at": "2026-08-02T18:14:22Z",
  "configuration": {
    "default_llm_model_key": "open_ai_responses_gpt_5_6_terra",
    "evals_default_llm_judge_model_key": "anthropic_claude_5_sonnet",
    "judge_model_key": "anthropic_claude_5_sonnet",
    "repeats": 5,
    "capture_model_completions": "full",
    "cases": null,
    "sample": null,
    "seed": null,
    "datasets": [
      { "eval_set": "SummarizationEvalSet", "name": "documents", "cases": 24, "digest": "sha256:9f2c..." }
    ],
    "code": { "git_sha": "4a91c0b7e2d3f8a6c5b4e3d2a1908f7e6d5c4b3a", "dirty": false }
  }
}
```

`run_at` is when the run started, which is also the timestamp in its filename. `evals_default_llm_judge_model_key` is the judge that was configured and `judge_model_key` is the one the run actually used, which are the same thing unless no judge was configured - in which case the setting is `null` and `judge_model_key` is [the model under test](#configuring-the-judge-llm-model).

### What Was Measured

Two keys in the block record the inputs rather than the settings, so a later reader can tell a model that changed from a dataset that did.

`datasets` has one entry per [dataset](#datasets) the run used: the eval set that declared it, its name, how many cases it holds, and a SHA-256 `digest` over those cases. The digest is taken over the cases sorted by id, with the keys inside each case sorted too, so reordering rows or reformatting the file leaves it alone while editing an input, an `expected`, or the set of cases changes it. A run that used no dataset records an empty list, which is how a reader tells it from a run written before this was recorded. When [`--cases` or `--sample`](#selecting-cases-to-run) narrowed a dataset, the entry also carries `selected`; `cases` is always the whole dataset, since the selection itself is already recorded above.

This matters because [`evals:compare`](#comparing-runs) joins the two runs on case id. Edit one line of `documents.jsonl`, re-run, and without the digest the difference is reported as the model behaving differently on the same input. With it, the comparison warns that the datasets are not the same before you read anything else. `--resume` is stricter: a dataset whose contents changed while the run was interrupted is refused outright, since the two halves of the results file would describe different inputs under one case id. Only the datasets both the log and the resuming invocation resolved are compared, so a resume narrowed to one eval set file still works.

`code` is the host app's git HEAD and whether the working tree was dirty, or `null` when the app is not a git checkout. Comparing one model before and after a prompt change is one of the two workflows `evals:compare` exists for, and nothing else in the results says which side of the change a run was on. Unlike everything else in the block, it does not constrain `--resume`: the commit that landed while a run was interrupted is often the one that fixed whatever interrupted it, so a resume across a commit warns and carries on rather than refusing.

Alongside `run_at` and `configuration`, the file has two more top-level keys:

- `results` - one entry per eval set, each an array with one result per execution of an eval block. A result carries its `description`, [`eval_id`](#eval-ids), `eval_index`, `passed`, `expectation_results`, any [`scores`](#scores), its [`usage` and `model_completions`](#captured-llm-calls), plus a `run_index` for [repeats](#repeating-evals) and a `case_id` for [dataset](#dataset-results) cases. A result that raised also carries `errored: true` - see [Errors Are Not Failures](#errors-are-not-failures).
- `summary` - run-wide totals across every eval, plus an `eval_pass_rates` array with one row per eval and a `score_summaries` array with one row per score name per eval.

This file is what [`evals:compare`](#comparing-runs) reads, so keep the runs you want to diff against.

### Eval Ids

Each result carries an `eval_id`, which is what identifies that eval across runs - the key [`evals:compare`](#comparing-runs) matches a baseline result to its candidate on, and the key `--resume` skips already-recorded work by. It looks like this:

```
SummarizationEvalSet#summarizes-the-article-7f3a91c0b4e2
```

Three parts: the eval set's class name, a slug of the eval's description, and the first 12 hex characters of `SHA256("<eval set class name>\n<description>")`. The digest is what actually identifies the eval - it's taken over the description verbatim, so `"handles > 100 items"` and `"handles < 100 items"` stay distinct even though they slug identically - and the slug in front of it is there so a result row or a NOT COMPARABLE line is recognizable at a glance. The slug is capped at 60 characters; the digest is not affected by that.

Nothing to declare, but two consequences worth knowing:

- **Two evals in one eval set can't share a description.** Their ids would be identical, so their results would be joined as though they came from the same eval. Raif refuses at load time rather than blending them, and names the description to reword.
- **Rewording a description produces a new id.** A comparison then reports the old eval as disappearing and the new one as arriving, rather than diffing the two as the same eval. That's usually right - a reworded eval is usually a changed eval. When it isn't, pass `id:` to keep the old identity across the rewording:

```ruby
eval "counts words, ignoring markdown syntax", id: "word-count" do
  # ...
end
```

A declared `id:` replaces the slug-and-digest half, so the example above is `SummarizationEvalSet#word-count`. It has to be unique within the eval set, and may contain letters, numbers, and any of `_ . : -`.

`eval_index`, also on every result, is the eval block's position in its set. It's what puts results back into definition order within one run, and is not an identity: inserting an eval block shifts every index below it.

### Errors Are Not Failures

An eval can end three ways, not two. It can pass, it can fail, or it can raise - a 429 from the provider, a socket timeout, a bad fixture in `setup`, a `JSON::ParserError` on a malformed response. The first two are measurements of your model's output. The third is not a measurement at all, and Raif keeps it separate everywhere:

- The result carries `errored: true` alongside `passed: false`, and the expectation that raised has `"status": "error"` rather than `"failed"`.
- The console prints `!` in yellow for that case rather than a red `✗`, and the run summary counts `N errored` on its own line rather than folding it into `N failed`.
- **Errored runs leave the pass-rate denominator.** An eval that ran 4 times, passed 3 and errored once reports `3/3` - a `pass_rate` of `1.0`, not `0.75`. `summary.eval_pass_rates` rows carry an `errored` count next to `runs` and `passed` so the denominator is legible.
- When *every* run of an eval or a case errored, its `pass_rate` is `null` rather than `0.0`. Nothing was measured, and a zero would claim it all failed. [`evals:compare`](#comparing-runs) reports those under NOT COMPARABLE, the same as a case only one run has.

[`evals:compare`](#comparing-runs) reports what each run lost to errors as its own section, so a run that got worse and a run that got flakier are not the same finding:

```
ERROR RATES (1)
  DocumentSummarizationEvalSet  produces expected output
    0.00 -> 0.12  0/24 -> 3/24 runs errored

NOT COMPARABLE (1)
  DocumentSummarizationEvalSet  produces expected output
    quarterly-report     candidate: all 3 runs errored

SUMMARY
  evals errored         0/24 (0.0%) -> 3/24 (12.5%)
  gate declined: 12.5% of runs errored, above the 5% ceiling (exit 2)
```

The reason for all of this is CI. If an error counts as a failure, a rate-limited afternoon reads as a model regression and fails the build, and the usual response to that is to disable the gate. `evals:compare` goes one step further and [refuses to gate at all](#what-the-gate-requires) when too many runs errored.

Errors are also retried before they get this far: transient provider failures (rate limits, timeouts, 5xx) are retried with jittered exponential backoff, honoring a `Retry-After` header when the provider sends one. What reaches the results file is what survived that.

## Resuming an Interrupted Run

The results file above is written once, after every eval set has finished. On its own that would mean a run killed at case 48 of 50 - by Ctrl-C, a provider outage, a rate limit cascade, the process running out of memory - loses every result it already paid for.

So each result is also appended to a run log the moment it completes, at `raif_evals/results/<run name>.partial.jsonl`. It's JSON Lines: a header line identifying the run and listing the executions it set out to perform, then one line per eval result. A run that stops early tells you what it has and how to pick it up:

```
Run interrupted.
38 results were recorded before it stopped: raif_evals/results/eval_run_20260805_094122_anthropic_claude_5_sonnet.partial.jsonl
Resume with: bundle exec raif evals --resume raif_evals/results/eval_run_20260805_094122_anthropic_claude_5_sonnet.partial.jsonl
```

`--resume` (or `RAIF_EVAL_RESUME`) reads the log back and skips every execution it already holds, keyed on the same tuple that identifies a result in the JSON: [which eval block](#eval-ids), which dataset case, which repeat. Because that key is the eval's id rather than its position, editing the file around an eval - adding one above it, reordering - doesn't confuse a resume about which results it already has. Only the work that never finished costs anything the second time. The resumed run completes the results file its first attempt was headed for - same name, same `run_at` - rather than opening a second file describing the same run, and the log is deleted once that file exists.

Some specifics worth knowing:

- **A sampled run resumes on the seed it recorded.** `--sample` without `--seed` still writes the seed it drew into the log header, and the resumed invocation samples on that rather than drawing again, so it continues the same subset of cases. Passing an explicit `--seed` that differs from the logged one is a configuration mismatch and is refused, per the next point.
- **The whole configuration has to match.** Every key in the results `configuration` block either changes what a result means (which model produced it, which model judged it, how much of each call was captured) or which cases produce one (`cases`, `sample`, `seed`, `repeats`). A resume that let any of them drift would write one results file describing a run that never happened, so a mismatch is refused and names the keys that moved. Re-run with the settings the log was started with, or drop `--resume` to start fresh.
- **An edited dataset is refused; edited code is only reported.** A [dataset whose fingerprint moved](#what-was-measured) is a configuration mismatch like any other, since the two halves of the results file would describe different inputs under one case id. The `code` key is deliberately not held to that standard - the commit that landed while a run was interrupted is often the one that fixed whatever interrupted it - so a resume across a commit prints a warning and carries on. The results file then names one commit for work produced under two, which is why it says so.
- **A truncated last line is skipped, not fatal.** A hard kill lands mid-write. Losing the one result being appended is the cost of appending; losing the run over it would defeat the purpose.
- **Results are carried forward for eval sets the resumed invocation doesn't visit.** Resuming with a narrower set of files keeps what the log already holds for the others.
- **The log, not the invocation, decides when the run is finished.** The header records the run's plan: every [eval id](#eval-ids), dataset case and repeat the run set out to execute. The results file is written and the log deleted only once a result exists for all of them. So a resume narrowed to one eval set file runs that file, then reports what is still outstanding and leaves the log in place:

  ```
  Run incomplete: 12 of 50 planned evals have not run, so no results file was written.
    DocumentEvalSet: 12
  38 results are recorded: raif_evals/results/eval_run_20260805_094122_anthropic_claude_5_sonnet.partial.jsonl
  Finish the run with: bundle exec raif evals --resume raif_evals/results/eval_run_20260805_094122_anthropic_claude_5_sonnet.partial.jsonl
  ```

  An eval block added to a file while the run was interrupted is work the run now owes too: the resume appends it to the plan and the run isn't finished until it has run.
- **A log written without a plan is refused.** Its finished work can't be told from its outstanding work, so there is no safe way to finish it. Start a new run.
- **A run that stopped before recording anything deletes its own log**, since there is nothing there to resume.

If you keep result files in version control, add `raif_evals/results/*.partial.jsonl` to your `.gitignore` - a log is transient, and the run it belongs to either finishes and replaces it or gets resumed.

## Running Evals Concurrently

An eval run is almost entirely spent waiting for provider responses. A 30-case dataset at `--repeat 5` with a judge call per case is 300 sequential round trips - half an hour in which your CPU does nothing. `--concurrency N` (or `RAIF_EVAL_CONCURRENCY=N`, or `Raif.config.evals_concurrency` in your initializer) overlaps that waiting across N threads:

```bash
bundle exec raif evals --concurrency 8
```

The default is 1, and the serial path is unchanged: same order, same output, no threads.

The whole run's work - every eval, every dataset case, every repeat, across every eval set - is listed before any of it executes, so the threads stay busy across eval set boundaries rather than draining a pool at the end of each set. Raising concurrency changes nothing about what a result means, which is why `--resume` will happily resume a run at a different concurrency than the one that started it.

Before turning it up, three things need to be true:

- **Your database connection pool has to be bigger than the concurrency.** Each eval takes a connection for the transaction it runs in, so `--concurrency 8` against the default `pool: 5` would spend the run timing out on checkouts rather than on inference. Raif checks this at startup and refuses to run rather than letting you find out at case 40; raise `pool:` for your test environment in `config/database.yml`. On sqlite3 concurrency is capped to 1 instead - concurrent write transactions against one file serialize on `SQLITE_BUSY`, so the threads would only add contention.
- **Your provider rate limit has to absorb it.** Concurrency turns 429s from rare into routine. Raif retries them with exponential backoff and honors a `Retry-After` header when the provider sends one (see `Raif.config.llm_request_max_retries`), but a concurrency well past your tokens-per-minute limit just converts wall clock into retry sleep. Start around 4-8 and watch for retries in the logs.
- **Your evals have to be independent of each other.** They already need to be - each eval runs in its own transaction that is rolled back - but concurrency makes it visible: two evals running at once are in two uncommitted transactions on two connections, so neither can see what the other created. An eval that depends on data another eval's `setup` left behind was already relying on something Raif does not promise, and will start failing here.

Two things about the console output change:

- **Lines arrive in completion order, not definition order.** Every line carries its case id, and each eval's description is printed the first time one of its results lands. The results file is unaffected: it is always written back in definition order, so two runs of the same work produce the same file whatever concurrency produced them.
- **Each execution's lines are written as one block.** A case summary and the failing expectations beneath it are emitted together rather than being interleaved with whatever else finished at the same moment.

Ctrl-C still works. Workers stop before picking up their next execution and the in-flight ones are allowed to finish and be recorded, so everything already paid for reaches the run log and the run stays resumable.

## Repeating Evals

LLM responses vary between runs, so a single pass/fail per eval cannot separate a real quality difference from one unlucky sample. `--repeat N` (or `RAIF_EVAL_REPEATS=N`) runs each eval N times, re-running `setup` and the eval block for each so the repeats are independent samples rather than a re-scoring of one response.

Repeats sample the model, not your inputs. To vary the input as well, give the eval a [dataset](#datasets) - the two compose, and the run becomes cases &times; repeats.

Each result gains a `run_index`, and the run's `summary` gains an `eval_pass_rates` array with one row per distinct eval, keyed on [`eval_id`](#eval-ids):

```json
{
  "eval_set": "MyEvalSet",
  "description": "produces expected output",
  "eval_id": "MyEvalSet#produces-expected-output-9c1de4a70b2f",
  "runs": 5,
  "errored": 0,
  "passed": 4,
  "pass_rate": 0.8
}
```

`errored` counts the runs that raised rather than producing a measurement; they are excluded from `pass_rate`'s denominator, so `runs - errored` is what `passed` is out of. See [Errors Are Not Failures](#errors-are-not-failures).

Pass rates are printed to the console at the end of the run. This is the number to compare when evaluating one model against another.

## Setting the LLM for Evals

Raif defaults to using `Raif.config.default_llm_model_key` for LLM API calls. You can override this setting via the `RAIF_DEFAULT_LLM_MODEL_KEY` environment variable.

```bash
RAIF_DEFAULT_LLM_MODEL_KEY=anthropic_claude_5_sonnet bundle exec raif evals
```

## Verbose Output

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

This is particularly useful when working with [LLM judges](#llm-as-judge-expectations) to understand why they made certain decisions.

## Captured LLM Calls

Every LLM call made during an eval is captured and included in the [results JSON](#results). Because each eval runs in a transaction that is rolled back, these records are captured before the rollback so they're preserved in the results even though the underlying `Raif::ModelCompletion` rows are not persisted.

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

### Judge Spend Is Reported Apart

LLM calls made by [LLM judges](#llm-as-judge-expectations) run inside the eval, so they are captured and counted in the totals above alongside the calls made by the code under test. They are also counted again on their own: a result whose eval called a judge gains a `judge_usage` object of the same shape as `usage`, and the run's `summary` gains `total_judge_model_completions`, `total_judge_tokens`, and `total_judge_cost`. These are a *subset* of the `usage` and `total_*` figures, not spend beside them.

The split exists for comparisons. The judge is meant to be the same model on both sides - `evals:compare` [refuses two different judges](#configuring-the-judge-llm-model) - so its spend is not part of what separates two models under test. It does not cancel out either, because a wordier model gives the judge more to read. A single `total cost $1.10 -> $1.64` row therefore blends "this model is more expensive" with "this model made the judge work harder". Both the run summary and `evals:compare` print the two lines instead:

```
LLM Usage:
  48 LLM calls
  $1.104200 total cost
    $0.903100 model under test
    $0.201100 judge (24 calls)
```

A result whose eval called no judge has no `judge_usage` key at all, and a results file written before this was recorded has none either - which is why `evals:compare` prints `-` rather than `$0.00` for a run whose judge spend is unknown.

Calls your `setup` or `teardown` blocks make are treated differently. They are not the eval's own measurement - a fixture built by an LLM is not what the eval is testing - so they stay out of `usage` and out of the `total_*` figures above. But they are real spend, so they are reported rather than dropped: a result whose setup or teardown made any gains an `overhead_usage` object of the same shape as `usage`, the run's `summary` gains `total_overhead_model_completions`, `total_overhead_tokens`, and `total_overhead_cost`, and the console prints an extra line under `LLM Usage`. A result whose setup and teardown made no calls - the normal case - has no `overhead_usage` key at all.

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

    expect_includes(task.parsed_response, eval_case.expected["subject"],
      label: "mentions the document's main subject")

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

`setup`, `teardown`, and the `eval` block all accept the case as an optional block argument. Blocks that don't declare one are called as before, so adding a dataset to an eval set never requires touching its other evals.

A case is an input (i.e. a single row in a dataset), not a run. The `eval` block is the procedure; the case is what you feed it. Raif runs the block once per case, times the number of [repeats](#repeating-evals).

Two things to know about how the pieces fit together in one file:

- **Declare a dataset above the evals that use it.** `dataset:` is checked when the class body loads, so a name that has not been declared yet raises there rather than silently running zero cases.
- **`setup` and `teardown` are shared by every eval in the set**, so an eval set that mixes dataset and non-dataset evals hands them a `nil` case for the non-dataset ones.

## Dataset Shape

A dataset is a block that returns an array of cases. The eval will be run against each case in the dataset. Each case is a Hash with up to three keys:

- `id` (**required**) - identifies the case in the console, the [results JSON](#results), and [comparisons](#comparing-runs). Ids must be unique within a dataset. A missing or duplicated id raises when the dataset loads, before any LLM call is made, because a case that can't be told apart from another can't be compared against its own past results.
- `input` (**required**) - whatever your `setup` and `eval` blocks need to build the case.
- `expected` (optional) - ground truth to assert against, for cases where you have a known-correct answer. See [Ground Truth Matchers](#ground-truth-matchers) for the helpers that compare against it.

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

Sampling without a `--seed` draws different cases each run, which makes two runs uncomparable case-for-case. The same seed and sample size draw the same cases again. The draw is over the case ids, not over the order the rows are written in, so reordering or reformatting a dataset file leaves the sample alone - the same thing its [digest](#what-was-measured) promises. The cases that are drawn still run in dataset order.

A sampled run always ends up with a seed even if you did not pass one: Raif draws one, prints it in the run header, and records it in the results `configuration` block. So a run you sampled without thinking about seeds can still be repeated case-for-case afterwards, and [resuming](#resuming-an-interrupted-run) it picks the sample back up rather than drawing a fresh one and finishing the results file with two unrelated samples in it.

`--cases` filters every dataset in the run, so an id that belongs to one eval set's dataset simply skips the others. If it matches nothing anywhere, the run exits non-zero rather than reporting a suite of zero evals that passed.

## Dataset Results

Each result in the [results JSON](#results) carries the `case_id` that produced it, alongside the existing [`eval_id`](#eval-ids), `eval_index`, and `run_index`. In `summary.eval_pass_rates`, an eval with a dataset reports its overall rate across every case and repeat, plus a `per_case` breakdown:

```json
{
  "eval_set": "Raif::Evals::Tasks::DocumentSummarizationEvalSet",
  "description": "produces expected output",
  "eval_id": "Raif::Evals::Tasks::DocumentSummarizationEvalSet#produces-expected-output-9c1de4a70b2f",
  "eval_index": 0,
  "cases": 3,
  "repeats": 2,
  "runs": 6,
  "errored": 0,
  "passed": 5,
  "pass_rate": 0.8333,
  "per_case": [
    { "case_id": "climate-report", "runs": 2, "errored": 0, "passed": 2, "pass_rate": 1.0 },
    { "case_id": "earnings-call",  "runs": 2, "errored": 0, "passed": 2, "pass_rate": 1.0 },
    { "case_id": "press-release",  "runs": 2, "errored": 0, "passed": 1, "pass_rate": 0.5 }
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
  ! quarterly-report run 1  0/1 expectations
      ✗ Setup execution
```

The `!` in the last line is an eval that raised rather than failed - see [Errors Are Not Failures](#errors-are-not-failures).

A failing expectation's description is truncated to 100 characters on these lines. An [LLM judge](#llm-as-judge-expectations) expectation is described by its whole criteria, and the same one repeats under every case that failed it, so at full length it buries the case ids and counts the lines exist to show. Pass `label:` to the judge helpers to choose what appears here; the untruncated text is always in the results JSON, the HTML comparison report, and `--verbose` output.

Use [`--verbose`](#verbose-output) (or `Raif.config.evals_verbose_output`) to get the full per-expectation output for every case. An app that turned verbose output on in its initializer gets the compact output back with `--no-verbose`, since a dataset at `--repeat 2` prints several hundred lines of judge reasoning under verbose.

# Adding Result Metadata to Expectations

You can attach metadata to any `expect` block to capture additional context that will be stored in the [results JSON file](#results). This is useful for tracking scores, metrics, or other relevant information alongside pass/fail results.

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

# Ground Truth Matchers

When a case has a known-correct answer, four matchers compare against it. Each one is an `expect` block underneath, so it counts toward the eval's pass rate and matches across runs like any other expectation.

```ruby
eval "extracts the invoice fields", dataset: :invoices do |eval_case|
  task = Raif::Tasks::InvoiceExtraction.run(creator: @user, document: @document)
  fields = task.parsed_response

  expect_exact_match(fields["vendor"], eval_case.expected["vendor"])
  expect_includes(fields["summary"], eval_case.expected["keywords"])
  expect_matches(fields["invoice_number"], /\A[A-Z]{2}-\d{4}\z/)
  expect_within(fields["total"], eval_case.expected["total"], percent: 1)
end
```

| Matcher | Passes when |
| --- | --- |
| `expect_exact_match(actual, expected)` | The two values are equal. Strings are stripped and downcased first; pass `strip: false` or `ignore_case: false` to compare them as they are. Non-strings are compared with `==`, so `false` and `42` are not coerced through `to_s`. |
| `expect_includes(actual, expected)` | Every expected text appears in `actual.to_s`. `expected` is a String or an Array of Strings, and an Array requires all of them. Pass `ignore_case: false` for a case-sensitive search. |
| `expect_matches(actual, pattern)` | `actual.to_s` matches the pattern. A String pattern is compiled to a Regexp, so a dataset row can carry one. |
| `expect_within(actual, expected, delta:)` | The two numbers differ by no more than the tolerance. Give `delta:` for an absolute tolerance or `percent:` for a relative one, and exactly one of the two. A non-numeric `actual` fails; a non-numeric `expected` raises, since only your eval put it there. |

Every matcher records what it compared as [result metadata](#adding-result-metadata-to-expectations), which a hand-written `expect` block does not:

```json
{
  "description": "includes expected text",
  "status": "failed",
  "metadata": {
    "actual": "The company reported strong quarterly results.",
    "expected": "[\"revenue\", \"margin\", \"guidance\"]",
    "missing": ["margin", "guidance"]
  }
}
```

Values longer than 500 characters are truncated, so a long response does not become most of the results file.

## Naming Matcher Expectations

A matcher's default description names the check and not the value: `exact match`, `includes expected text`, `matches expected pattern`, `within 0.5 of expected`. That is deliberate. [`evals:compare`](#comparing-runs) tallies an expectation across the cases of an eval by its description, so a description carrying case data would split into one tally per case, and the regression gate would read a rate measured on a single case.

Pass `label:` when a check deserves a better name, or when one eval uses the same matcher twice:

```ruby
expect_includes(task.parsed_response, eval_case.expected["subject"], label: "mentions the main subject")
expect_includes(task.parsed_response, eval_case.expected["author"], label: "credits the author")
```

Keep values that vary per case out of a `label:`, for the same reason.

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

Each eval result in the [results JSON](#results) gains a `scores` array:

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
  "eval_id": "Raif::Evals::Tasks::DocumentSummarizationEvalSet#produces-expected-output-9c1de4a70b2f",
  "eval_index": 0,
  "name": "clarity",
  "scale": "1..5",
  "higher_is_better": true,
  "n": 6,
  "spread_n": 3,
  "mean": 4.33,
  "median": 4.5,
  "stddev": 0.2887,
  "min": 4.0,
  "max": 5.0,
  "ci95": [4.0, 4.5],
  "per_case": [
    { "case_id": "climate-report", "n": 2, "mean": 4.5 },
    { "case_id": "earnings-call",  "n": 2, "mean": 4.5 },
    { "case_id": "press-release",  "n": 2, "mean": 4.0 }
  ]
}
```

`min` and `max` here are the lowest and highest values the run actually observed, not the gate. The identically named keys in an individual result's `scores` array are the `min:`/`max:` bounds passed to `score`, so the same two names mean the threshold in one place and the range in the other.

`per_case` is present only for a [dataset](#datasets) eval, since without cases there is nothing to break the mean down by. `stddev` and `ci95` are reported alongside the mean because two models a tenth of a point apart with a standard deviation of half a point have not been distinguished.

**`stddev` and `ci95` are over cases, not over every observation** - which is what `spread_n` records, and why it is smaller than `n` in the example above: 3 cases, 6 observations. Pooling all 6 would mix two unrelated things, real differences between the inputs and repeat-to-repeat noise on one input, and on a dataset of any breadth the first dominates. That pooled number describes how varied your dataset is, where what a reader needs beside a mean is how uncertain the mean is. For an eval with no dataset there are no cases, so both are over the individual values and `spread_n` equals `n`.

`stddev` is the sample standard deviation (dividing by n-1). These values are draws from the model's output distribution rather than the whole of it - that is what `--repeat` exists to sample - and dividing by n instead understates the spread by 0.71x at 2 values and 0.89x at 5, which is exactly the range these runs live in. Understating it would defeat the only reason it is printed. (This is a partial correction, not a complete one: the square root of an unbiased variance is still biased low. `ci95` is the figure to lean on when the difference matters, since it does not depend on that assumption.)

`ci95` is a 95% percentile bootstrap confidence interval, resampled from a fixed seed so the same numbers always produce the same interval.

**`ci95` needs at least 5 values and says so when it does not have them.** A bootstrap can only be as informative as the number of values it resamples: 3 values have 10 distinct resamples between them, so the interval restates those three rather than inferring from them, and its real coverage is neither 95% nor stable. Printing one anyway invites exactly the over-reading it was added to prevent. Below 5 the key is replaced with `ci95_omitted`, naming what it was short of:

```json
"spread_n": 3,
"ci95_omitted": "3 cases; a 95% interval needs 5"
```

The count is in the unit the spread was measured in - cases for a dataset eval, runs otherwise - since that is what you would have to add more of. The console prints the same fragment beside the mean. Note that this is the same floor the [regression gate](#what-the-gate-requires) runs into from the other direction: a handful of cases genuinely cannot support an inference, whichever test is asked for one.

`stddev` is omitted below 2 values, where the arithmetic returns `0.0` - which in a summary read to decide whether a difference is real would claim a spread had been measured when none was.

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

Or you can provide the rubric as a string, in which case `score_name:` is required:

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
  min_passing_score: 7,
  score_name: "code_quality"
)
```

A `ScoringRubric` object names the [score](#scores) it produces via its own `name:`. A string rubric has no name, and the score name is the metric the run summary aggregates by and [`evals:compare`](#comparing-runs) joins on, so Raif raises rather than recording an unidentifiable metric. The check happens before the judge runs, so it costs nothing to hit.





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

**Configure this before you rely on judge scores.** With no judge configured, judging falls back to `Raif.config.default_llm_model_key` - the model being evaluated grades its own output. A model asked to score its own work tends to score it generously (self-preference bias), and it makes the headline use case for these evals actively misleading: running the same suite against a second model with `RAIF_DEFAULT_LLM_MODEL_KEY` switches the judge along with the subject, so the two runs are scored by two different rulers. A run whose judge is the model under test says so in its header and warns before spending anything:

```
Raif.config.evals_default_llm_judge_model_key: (not set - judged by open_ai_gpt_5_6_terra, the model under test)

Warning: any LLM judge expectation in this run will be graded by open_ai_gpt_5_6_terra, the model under test.
```

Two rules of thumb when picking one:

- **Hold the judge fixed across everything you intend to compare.** [`evals:compare`](#comparing-runs) refuses to diff two runs judged by different models for this reason. Each run records the judge it actually used, so two unconfigured runs of two different models are caught as the mismatch they are rather than passing as a comparison.
- **Prefer a model from outside the family under test**, since self-preference extends to a model's siblings. Judging is short, structured, and cheap relative to the task being judged, so a capable judge from another provider is usually worth it.

Judge calls are LLM calls: they are captured in the results and counted in the run's cost totals, so a fixed judge also keeps that overhead comparable between runs.

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

Once you have two [result files](#results), `evals:compare` diffs them:

```bash
bundle exec raif evals:compare \
  raif_evals/results/eval_run_20260804_180216_open_ai_responses_gpt_5_4.json \
  raif_evals/results/eval_run_20260805_094122_anthropic_claude_5_sonnet.json
```

The first file is the baseline and the second is the candidate. The two most common uses are comparing two models on the same prompts, and comparing the same model before and after a prompt change.

Results are matched on [`eval_id`](#eval-ids), `case_id`, and expectation description. Cases are matched individually because a model can improve on average while getting materially worse on one input, which an average alone does not show.

That matching is only as good as the inputs behind it, so the command also checks [what each run measured](#what-was-measured). If the two runs' dataset fingerprints differ, it warns loudly and continues - comparing a widened dataset against its predecessor is a legitimate thing to do, as long as you know that is what you are looking at:

```
Warning: these two runs did not measure the same datasets:
  documents (SummarizationEvalSet): 24 cases sha256:9f2c... -> 25 cases sha256:1b7e...
  Cases are joined by id, so a difference the dataset caused reads as a difference the model caused.
  Re-run the baseline against the current dataset to compare the two models alone.
```

The `total cost` row is split into the model under test and [the judge](#judge-spend-is-reported-apart), since the judge is held fixed across the comparison and its spend is not part of what separates the two models.

```
Comparing eval runs

  baseline   open_ai_responses_gpt_5_4   2026-08-04 18:02   2 evals x 3 repeats   4 cases   $1.10   eval_run_..._gpt_5_4.json
  candidate  anthropic_claude_5_sonnet   2026-08-05 09:41   2 evals x 3 repeats   4 cases   $1.64   eval_run_..._claude_5_sonnet.json
  judge      anthropic_claude_5_haiku (both runs)
  code       4a91c0b7e2d3 -> 4a91c0b7e2d3

NEW FAILURES (1)
  DocumentSummarizationEvalSet  produces expected output
    press-release        1.00 -> 0.33
      1.00 -> 0.33  summary is between 100 and 1000 words

FIXED (1)
  DocumentSummarizationEvalSet  handles documents that are too short to summarize
    stub-document        0.33 -> 1.00
      0.33 -> 1.00  returns exactly the text 'Unable to generate summary'

SCORE MOVES (2)
  clarity  4.1111 -> 4.5556  +0.4445  (+10.8%, n=18, over 6 cases, sd 0.5137 -> 0.4157)
    climate-report       4.3333 -> 5.0  +0.6667
    earnings-call        4.0 -> 4.6667  +0.6667
    press-release        4.0 -> 4.0  0.0
  summary_word_count  284.0 -> 412.0  +128.0  (+45.1%, n=18, over 6 cases, sd 31.2 -> 44.7, not gated)

NOT COMPARABLE (1)
  DocumentSummarizationEvalSet  produces expected output
    quarterly-report     candidate only

REGRESSION GATE (1)
  DocumentSummarizationEvalSet  produces expected output (pass_rate)
    67% worse, 0.6667 absolute   1/1 cases worse, p=1.0

SUMMARY
  evals passed          16/18 -> 17/18
  expectations          70/72 -> 71/72
  mean clarity          4.1111 -> 4.5556
  mean summary_word_count 284.0 -> 412.0
  total cost            $1.10 -> $1.64
    model under test    $0.90 -> $1.40
    judge               $0.20 -> $0.24
  1 regression beyond --fail-on-regression 0.25 (25% worse than baseline), none distinguishable from run-to-run variation at a family-wise 0.05 over 1 candidate row
```

Options:

```bash
# Exit non-zero when a pass rate or a gated score gets more than this much worse than the
# baseline, as a fraction of it: 0.25 means "25% worse". Without it, regressions are still
# reported and the command exits 0.
--fail-on-regression 0.25

# Family-wise significance level a regression must clear as well as the size threshold
# (default 0.05). 1 waives the requirement and gates on the point estimate alone.
--significance 0.05

# text (default), json, or html. html writes a self-contained file next to the results.
--format html

# Compare runs that used different judge models anyway (see below)
--allow-judge-mismatch

# Fraction of runs either side may lose to errors before --fail-on-regression declines to
# decide (default 0.05). 1 gates on the surviving runs regardless.
--max-error-rate 0.05
```

Some specific behaviors:

- **Cases present in only one run are reported under NOT COMPARABLE, never dropped.** A silently omitted case is indistinguishable from agreement. An expectation that exists on only one side is reported the same way, which is what a renamed description looks like.
- **Errors are reported apart from failures.** Runs that raised are excluded from the pass rates rather than counted as misses, so a flaky provider does not read as a quality regression. What each side lost to errors is reported under ERROR RATES and in the SUMMARY, and a case that errored on every run of a side is reported under NOT COMPARABLE - it measured nothing, which is the same problem as a case only one run has. See [Errors Are Not Failures](#errors-are-not-failures).
- **Runs judged by different models are refused.** Scores from two different [judge models](#configuring-the-judge-llm-model) measure two different things, so the command exits 2 without printing a comparison. This compares the judge each run actually used, so it also catches the case where neither run configured a judge and each was therefore graded by its own model under test. `--allow-judge-mismatch` overrides this and labels the output accordingly.
- **Score direction is honored.** A score declared `higher_is_better: false` counts a decrease as an improvement, and ungated observational scores are reported but never trip `--fail-on-regression`.
- **The threshold is relative to the baseline, not absolute.** A pass rate, a 1-5 rubric score, and a latency in milliseconds are not in the same units, so one absolute threshold cannot mean the same thing to all three: `0.25` would ask for a quarter of an eval's runs on one row and a quarter of a millisecond on the next, which makes the flag fire on noise until you turn it off. Each regression is divided by what it started from instead, so `--fail-on-regression 0.25` asks one question everywhere - did anything get more than 25% worse. A `clarity` mean of 4.0 dropping to 3.6 is `0.1`; an `elapsed_ms` mean of 1000 rising to 1200 is `0.2`. Score moves print their relative change next to the absolute one so you can see which rows are near the threshold. For a pass rate that started at 1.0 - an eval that used to pass every run - the relative and absolute readings are the same number, so the common case reads exactly as you would expect.
- **A regression from a baseline of zero has no fraction to take, and trips any threshold.** A gated `error_count` going from 0 to 3 is a real regression that cannot be expressed as a percentage of zero, so it is reported with a null magnitude and always fails the gate rather than being skipped for want of a denominator.
- **A case that traded one failure for another is a regression**, even though its pass rate did not drop. One failure traded for another is not a fix. A case whose rate held steady is reported under NEW FAILURES; a case that fixed more than it broke reads better under FIXED, but either way the expectation that dropped is listed beneath it and counts toward `--fail-on-regression`, so an improvement cannot hide the loss underneath it.
- **No Rails boot.** The command reads two JSON files and does arithmetic, so it does not load your application, need a database, or need an API key.

## What the Gate Requires

`--fail-on-regression` asks two questions, and a row has to answer both before the command exits 1:

1. **Is it big enough?** The relative threshold above.
2. **Is it consistent enough to tell apart from run-to-run variation?** LLM output varies between runs, so a threshold on point estimates alone fires on noise - and a gate that fires on noise gets disabled, which is worse than having no gate.

The second question is answered from the pairing the two runs already have. The same dataset cases ran on both sides, so each case is a matched pair, and the gate asks how surprising it would be for this many pairs to move the same way if the two runs were interchangeable. That is a [sign test](https://en.wikipedia.org/wiki/Sign_test), computed exactly. Cases that did not move are excluded rather than split - a case that scored the same on both runs is evidence for neither.

The report shows both halves, so a withheld verdict is legible rather than mysterious:

```
REGRESSION GATE (2)
  DocumentSummarizationEvalSet  produces expected output (pass_rate)
    100% worse, 1.0 absolute   8/8 cases worse, p=0.007813
  clarity (score)
    40% worse, 2.0 absolute   8/8 cases worse, p=0.007813
```

Some consequences worth knowing before you wire this into CI:

- **How many cases you need.** The sign test's smallest reachable p-value is set by the number of pairs, not by how large the regression is: 5 cases all moving the same way is `p = 0.0625`, 6 is `0.03125`, 8 is `0.0078`. Below about 6 cases no regression can clear the default 0.05 - not because the tooling is being cautious, but because 5 matched pairs genuinely cannot distinguish a consistent move from a coin flip. Widen the dataset, or lower the bar deliberately with `--significance`.
- **`--repeat` does not create pairs.** Repeats sharpen each case's own estimate, which makes its direction more reliable; cases are what the test counts. A run with many repeats and one case still has one pair.
- **The level is divided by the number of rows tested.** The gate fails if *any* row regresses, so testing 20 rows at 0.05 each would fail one run in three on noise alone. Each candidate row is tested at `0.05 / (number of candidate rows)` instead ([Bonferroni](https://en.wikipedia.org/wiki/Bonferroni_correction)), so `0.05` means what it says about the run as a whole. Only rows that already cleared the size threshold are counted, which keeps the correction as loose as it can honestly be.
- **Evals with no dataset are handled differently.** A non-dataset eval has no matched unit, so its pass rate goes to a [Fisher exact test](https://en.wikipedia.org/wiki/Fisher%27s_exact_test) on the repeat counts on each side. That works - 5 of 5 passing against 0 of 5 is `p = 0.0079` - but it needs several repeats: at `--repeat 1` it returns `p = 1.0`, which is the right answer to "one draw against one draw".
- **A score on a non-dataset eval cannot be tested at all,** and the command says so rather than exiting 0 on it. There is no exact two-sample test for a continuous score at these counts, and approximating one would invent precision the data does not have. If every regression in a run is untestable, `evals:compare` exits **2** - refusing to decide, the same way it refuses two mismatched judges - rather than reporting a run that may well have regressed as clean. Give those evals a dataset, or pass `--significance 1`.
- **A run that lost too much to errors is not gated at all.** Excluding errored runs from the pass rates fixes the first-order problem, but not the second: if the runs that errored were not a random sample of the ones that did not - the long inputs are the ones that time out - the surviving denominator is a biased one. Past `--max-error-rate` (default `0.05`) on either side, `evals:compare` prints the comparison and then exits **2** rather than passing or failing, the same way it refuses two mismatched judges. Re-run the affected arm, or pass `--max-error-rate 1` to gate on the surviving runs anyway.
- **`--significance 1` restores gating on effect size alone.** Use it when you know the sample is too small for a verdict and you want the point estimate to gate anyway. It is the honest way to have the old behavior, and the report labels it: `evidence not required (--significance 1.0)`.

Pass rate rows are gated per eval rather than per case, since the cases are what the evidence is drawn from. Per-case detail is still reported under NEW FAILURES, where a single case that got worse is visible without being able to fail the build on its own.

