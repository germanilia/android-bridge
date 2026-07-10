# Second Brain Tab Code Summary

## Scope

- Renamed the Mac **Notes** surface to **Meetings**.
- Added a separate **Second Brain** tab mapped to `BRAIN_ROOT` or `~/second_brain`.
- Added per-task LLM routing for:
  - Summarize
  - Chat
  - Second Brain Search
  - Second Brain Q&A
  - Second Brain CRUD

## Implementation

### Mac UI

- `mac/Sources/BridgeApp/BridgeApp.swift`
  - Renamed tab/menu copy from Notes to Meetings.
  - Added `SecondBrainTab` with browse, read/edit, create note, delete note, search, and chat panels.
  - Added `LLMSettingsView` for per-task provider/model selection.

- `mac/Sources/BridgeApp/main.swift`
  - Renamed menu item to **Open Meetings**.
  - Added **Open Second Brain** menu item.

### Core services

- `mac/Sources/BridgeCore/MeetingCapture.swift`
  - Added `LLMFeature`, `LLMConfig`, and `LLMService`.
  - Summary/title/chat now route through `LLMService`.
  - Default is local Ollama (`gemma4:e4b`).
  - pi mode runs `pi --no-skills --skill ~/.agents/skills/second-brain` with the configured model.

- `mac/Sources/BridgeCore/SecondBrainStore.swift`
  - New wrapper around the second-brain skill CLI (`brain.py`).
  - Supports tree, show, search, add note, save, delete, and Q&A.

- `mac/Sources/BridgeCore/LinkManager.swift`
  - Publishes second-brain tree/content/search/chat state.
  - Exposes actions for refresh, select, search, save, create, delete, and chat.

- `mac/Sources/BridgeCore/SecondBrainExporter.swift`
  - Updated second-brain skill path from `~/.claude/skills/...` to `~/.agents/skills/...`.

## Validation

- `cd mac && swift build` ✅

## Notes

- Local Ollama remains the default for all LLM-backed tasks.
- Search uses the second-brain CLI by default; if pi is selected for Second Brain Search, the search request is delegated to pi with only the second-brain skill loaded.
- CRUD operations use the second-brain CLI where available and run `check` after changes.
