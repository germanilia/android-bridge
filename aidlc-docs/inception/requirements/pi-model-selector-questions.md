# pi Model Selector and Summary Backfill Questions

## Current understanding

- Replace the hard-coded pi model list with models returned by the locally configured `pi --list-models` command.
- Include authenticated OpenAI Codex models such as `openai-codex/gpt-5.4`.
- After choosing a model for Summarize, generate summaries for existing meetings that have transcripts but no generated summary.

## Question 1
When should missing-summary backfill run?

A) Automatically after the Summarize model changes, processing every meeting with a transcript and no generated summary

B) Show a confirmation before processing every meeting with a transcript and no generated summary

C) Add a separate Backfill Missing Summaries button; model selection alone does not start work

D) Other (please describe after [Answer]: tag below)

[Answer]: C
