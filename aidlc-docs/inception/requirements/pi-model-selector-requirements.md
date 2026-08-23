# pi Model Selector and Summary Backfill Requirements

## Intent analysis

- **User request**: Show the models configured in the local pi installation and provide a button that generates missing meeting summaries.
- **Request type**: Bug fix and enhancement
- **Scope**: Mac app model settings and meeting summary store
- **Complexity**: Simple

## Functional requirements

1. The pi model picker must load available models from the configured local pi executable instead of using a hard-coded list.
2. Model identifiers must use pi's `provider/model` form, including available OpenAI Codex entries such as `openai-codex/gpt-5.4`.
3. Failure to query pi models must be visible in the settings UI. The app must not silently substitute stale hard-coded models.
4. The Summarize settings row must provide a **Backfill Missing Summaries** button.
5. Selecting a model must save the selection but must not start backfill automatically.
6. Backfill must process meetings that have a non-empty transcript and no generated summary for the active summary language and type.
7. Backfill must preserve existing summaries and must not regenerate or overwrite them.
8. Backfill must use the currently selected Summarize provider and model.
9. The UI must show backfill progress and completion or failure status.

## Non-functional requirements

- Run pi discovery and summary generation outside the main UI thread.
- Keep local meeting files private; send transcript content only through the provider explicitly selected by the user.
- Add focused Swift tests for model-list parsing and missing-summary eligibility.
- Add no new dependency.

## Extension compliance

- **Security Baseline**: Compliant. No credentials added or logged; transcript processing follows explicit provider selection.
- **Resiliency Baseline**: N/A because this extension is disabled.
- **Property-Based Testing**: N/A for this bounded command-output parser and orchestration change; focused examples cover the relevant behavior.
