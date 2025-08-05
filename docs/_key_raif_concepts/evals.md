---
layout: default
title: Evals
nav_order: 5
description: "Create and run LLM evals to help you iterate, test, and improve your prompts"
---

{% include table-of-contents.md %}

# Evals Setup

Raif includes the ability to create and run LLM evals to help you iterate, test, and improve your prompts.

When you run the install command during [setup](../getting_started/setup#initial-setup), it will automatically set up evals for you.

If you want to set up evals manually, you can run:
```bash
raif evals:setup
```

This will:
- Create a `raif_evals` directory in your Rails project with a `setup.rb` file. This file is loaded automatically when you run your evals.
- Within `raif_evals`, it will also create the following directories:
  - `eval_sets` - Where your actual evals will go.
  - `files` - For any files (e.g. a PDF document or HTML page) that you want to use in your evals.
  - `results` - Where the results of your eval runs will be stored.


