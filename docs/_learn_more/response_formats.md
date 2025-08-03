---
layout: default
title: Response Formats
nav_order: 2
description: "Response formats & parsing for Raif"
---

{% include table-of-contents.md %}

When using Raif to interact with the LLM, you can specify the response format you want to receive. The response format will be one of `text`, `json`, or `html`.

You can specify the response format when [chatting directly with the LLM](../getting_started/chatting_with_the_llm), or when creating a [Task](../key_raif_concepts/tasks) or [Conversation](../key_raif_concepts/conversations).

# JSON Response Format

When using the `json` response format, Raif will:

1. Strip any markdown code fences inserted by the LLM
2. Parse the response as JSON.

If you're using the OpenAI adapter, Raif will automatically enable OpenAI's [JSON mode](https://platform.openai.com/docs/guides/structured-outputs#json-mode){:target="_blank"} feature. 

And if you define a [JSON schema](../learn_more/json_schemas), it will trigger utilization of OpenAI's [structured outputs](https://platform.openai.com/docs/guides/structured-outputs?api-mode=chat#structured-outputs){:target="_blank"} feature, which will force the response to adhere to your schema.




# HTML Response Format

When using the `html` response format, Raif will:

1. Strip any markdown code fences inserted by the LLM
2. Convert markdown links to HTML links.
3. Strip `utm_` tracking parameters from URLs.
4. Sanitize the HTML using Rails' [`sanitize` method](https://api.rubyonrails.org/classes/ActionView/Helpers/SanitizeHelper.html#method-i-sanitize){:target="_blank"}. 

By default, Raif will use `Rails::HTML5::SafeListSanitizer.allowed_tags` and `Rails::HTML5::SafeListSanitizer.allowed_attributes`. 

You can override these using the `llm_response_allowed_tags` and `llm_response_allowed_tags` class methods. See the [`Raif::Tasks::DocumentSummarization` example task](../key_raif_concepts/tasks#html-response-format-tasks) for usage.


---

**Read next:** [Streaming Responses](streaming)
