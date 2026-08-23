# DDP2 macOS update client functional-design plan

## Scope

Design the native macOS stable-update flow against the frozen DDP1 schema-1 release contract. The unit discovers, validates, downloads, verifies, and opens a DMG only after explicit user consent. It never replaces the installed application.

## Inputs

- `aidlc-docs/inception/requirements/direct-distribution-packaging-requirements.md`
- `aidlc-docs/inception/application-design/direct-distribution-packaging-unit-of-work.md`
- `aidlc-docs/inception/application-design/direct-distribution-packaging-unit-of-work-story-map.md`
- `aidlc-docs/inception/application-design/direct-distribution-packaging-component-methods.md`
- `aidlc-docs/inception/application-design/direct-distribution-packaging-services.md`
- DDP1 `release-manifest.json` schema and stable asset names
- Existing BridgeCore, AppDelegate, Dashboard, and Settings boundaries

## Clarification assessment

No new user questions are required. The approved requirements, application design, frozen DDP1 contract, and prior direction to use recommended defaults resolve the functional choices. This design does not expand scope or weaken an approved security rule.

## Plan

- [x] Confirm DDP2 boundaries, dependencies, owned requirements, and exclusions.
- [x] Freeze strict semantic-version and schema-1 decoding rules from DDP1.
- [x] Define stable GitHub Release selection, repository binding, host policy, and asset binding.
- [x] Define current-versus-available version decisions and platform compatibility checks.
- [x] Define automatic and manual discovery behavior without blocking launch.
- [x] Define explicit-consent, checksum-fetch, bounded-download, SHA-256, and temporary-file rules.
- [x] Define verified-DMG open behavior, installation guidance, retry, reveal, and cleanup.
- [x] Define typed failures and automatic-versus-manual presentation rules.
- [x] Define native controller state and Settings/update dialog components.
- [x] Define example-based Swift verification scenarios and acceptance-criterion traceability.
- [x] Generate domain entities, business logic, business rules, and frontend component artifacts.
- [x] Validate artifact structure, tables, paths, and text-only state-flow alternative.
- [x] Present Functional Design completion for explicit approval.

## Output

- `aidlc-docs/construction/direct-distribution-packaging-ddp2/functional-design/domain-entities.md`
- `aidlc-docs/construction/direct-distribution-packaging-ddp2/functional-design/business-logic-model.md`
- `aidlc-docs/construction/direct-distribution-packaging-ddp2/functional-design/business-rules.md`
- `aidlc-docs/construction/direct-distribution-packaging-ddp2/functional-design/frontend-components.md`
