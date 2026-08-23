# File Notification Copy Code Generation Plan

This file is the single source of truth for this bug fix.

## Unit Context
- **Unit**: Mac file notification toast
- **Requirement**: File-toast Copy writes the absolute saved-file path.
- **Dependency**: `LinkManager` already supplies `action=openFile` and `path` metadata.
- **Protocol/database impact**: None.
- **Security**: Path remains local and requires explicit Copy action.
- **PBT**: Enforced partial-mode properties are N/A; no transformation or serialization is added.

## Execution Steps
- [x] **Step 1 — Implement Copy selection**: Modified `mac/Sources/BridgeApp/main.swift` so file toasts copy `userInfo["path"]`; other toasts copy `body`.
- [x] **Step 2 — Verify source behavior**: Confirmed click-to-open remains unchanged and no duplicate source files were created.
- [x] **Step 3 — Run tests and debug build**: `swift test` passed 25 XCTest cases plus 100 SwiftCheck cases; `swift build` passed.
- [x] **Step 4 — Build and deploy**: Built with `android-bridge`, installed `/Applications/AndroidBridge.app`, confirmed matching binary SHA-256, and confirmed the process is running. Strict bundle verification still reports the pre-existing bundled MLX Whisper virtualenv symlink issue.
- [x] **Step 5 — Record artifacts and status**: Wrote the code summary, updated the build/test summary, audit entry, and state.

## Acceptance Mapping
- [x] **AC1**: File toast still displays `Click to open <filename>`.
- [x] **AC2**: Clicking toast still invokes `handleNotificationClick(userInfo)`.
- [x] **AC3**: Copy uses the exact absolute `path` for file notifications.
- [x] **AC4**: Non-file toast Copy continues using `body`.
- [x] **AC5**: Tests, build, installation, and launch succeeded.
