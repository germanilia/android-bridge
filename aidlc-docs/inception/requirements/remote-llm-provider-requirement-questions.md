# Remote LLM Provider — Requirement Clarification Questions

Please answer each question by filling in the letter choice after the [Answer]: tag.
If none of the options match, choose the last option (Other) and describe your preference.

## Question 1
How should the app talk to remote providers? LiteLLM exposes an OpenAI-compatible API, so one OpenAI-compatible HTTP client covers LiteLLM proxy, OpenAI, Z.AI, and (through LiteLLM) Bedrock — each provider is just a preset with its own base URL + API key + model name.

A) One OpenAI-compatible client with provider presets (Local/Ollama, LiteLLM proxy, OpenAI, Z.AI, Custom base URL). Bedrock is reached through your LiteLLM proxy. **(Recommended — smallest implementation)**

B) Same as A, but also add a native AWS Bedrock integration (SigV4 signing, AWS credentials) so Bedrock works without a LiteLLM proxy

C) Other (please describe after [Answer]: tag below)

[Answer]:

## Question 2
Remote transcription: the OpenAI-compatible standard is the `/v1/audio/transcriptions` endpoint (Whisper-style), which LiteLLM and OpenAI both support. Should remote transcription use that?

A) Yes — remote transcription uses the OpenAI-compatible audio transcriptions endpoint; local stays mlx_whisper **(Recommended)**

B) Transcription always stays local (mlx_whisper); only summary and chat get remote providers

C) Other (please describe after [Answer]: tag below)

[Answer]:

## Question 3
Where should API keys be stored? (Security Baseline extension is enabled for this project.)

A) macOS Keychain — keys never written to plain files **(Recommended, complies with Security Baseline SECURITY-12)**

B) UserDefaults like the other app settings — simpler, but plaintext on disk

C) Other (please describe after [Answer]: tag below)

[Answer]:

## Question 4
If a remote provider call fails (bad key, network down), what should happen?

A) Surface the error in the UI, no silent fallback **(Recommended — matches fail-fast preference)**

B) Automatically fall back to the local provider and note it in the UI

C) Other (please describe after [Answer]: tag below)

[Answer]:

## Question 5
Where should the provider settings UI live? There are three sections to configure (Summary, Transcription, Chat), each with provider / model / API key / base URL.

A) New "AI Providers" section in the Notes tab settings area (next to Summary language/type) **(Recommended — everything meeting-related stays in one place)**

B) A dedicated app Settings window (⌘,) with an AI Providers pane

C) Other (please describe after [Answer]: tag below)

[Answer]:

## Note (no answer needed)
Meeting **title generation** and **summary** currently use the same code path — the plan is that the Summary provider also controls title generation. "Chat" means the meeting Q&A feature. Say so under any [Answer]: tag if you want this different.
