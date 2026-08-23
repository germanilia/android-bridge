# Direct distribution packaging unit-of-work plan

## Objective

Decompose the approved release and updater design into implementation units with explicit ownership, dependencies, requirement coverage, and construction order.

## Progress

- [x] Read approved requirements and Application Design artifacts.
- [x] Confirm this is a brownfield monorepo enhancement, not independently deployed services.
- [x] Resolve decomposition questions below. All recommended options selected with no ambiguity.
- [x] Obtain approval of this decomposition plan. User directed all recommended choices and continuation toward code generation.
- [x] Generate `aidlc-docs/inception/application-design/direct-distribution-packaging-unit-of-work.md` with unit definitions and responsibilities.
- [x] Generate `aidlc-docs/inception/application-design/direct-distribution-packaging-unit-of-work-dependency.md` with the dependency matrix.
- [x] Generate `aidlc-docs/inception/application-design/direct-distribution-packaging-unit-of-work-story-map.md` mapping requirements and acceptance criteria to units.
- [x] Validate unit boundaries and dependency direction.
- [x] Ensure every functional requirement, NFR, and acceptance criterion has an owning unit.
- [x] Update this plan immediately when each step completes.

## Category assessment

- **Story grouping**: Applicable. No separate stories were generated, so functional requirements and installation/update journeys are the mapping source.
- **Dependencies**: Applicable. Both updater units depend on the release manifest and asset contract.
- **Team alignment**: Applicable. One repository and likely one maintainer favor clear module ownership without service boundaries.
- **Technical considerations**: Applicable. CI release tooling and native runtime code have different test and deployment surfaces.
- **Business domain**: Applicable. Distribution production, Mac updates, and Android updates are distinct user capabilities.
- **Greenfield code organization**: Not applicable. This is a brownfield monorepo and existing directories remain authoritative.

## Decomposition questions

### Q1. Unit grouping

How should the increment be divided?

- **A. Recommended**: Three units: release packaging/signing, macOS update client, and Android update client.
- **B. Two platform units**: Put shared release tooling into the Mac and Android units.
- **C. One unit**: Treat the whole increment as one cross-platform unit.
- **D. Four units**: Separate shared manifest/version tooling from release packaging, Mac updates, and Android updates.
- **E. Other**: Describe exact units.

[Answer]: A - use three units.

### Q2. Shared contract ownership

Which unit owns `VERSION`, manifest schema, asset names, and release validation?

- **A. Recommended**: Release packaging/signing owns and freezes the contract before updater implementation; updater units consume it and add language-specific decoders.
- **B. Mac updater owns it**: The release pipeline and Android client follow Swift definitions.
- **C. Android updater owns it**: The release pipeline and Mac client follow Kotlin definitions.
- **D. Joint ownership**: All units may change the contract independently during implementation.
- **E. Other**: Define the owner and change process.

[Answer]: A - Unit 1 owns and freezes the shared contract.

### Q3. Construction sequence

How should work proceed?

- **A. Recommended**: Complete release contract and local package tooling first; then implement Mac and Android updater units against the fixed contract; finish with integrated release validation.
- **B. Mac first**: Finish all Mac packaging and updates before any Android work.
- **C. Android first**: Finish Android signing and updates before any Mac work.
- **D. Fully parallel**: Start all units without a contract checkpoint.
- **E. Other**: Specify the sequence.

[Answer]: A - complete contract/tooling first, then platform updaters, then integration.

### Q4. Documentation ownership

Where should public installation and maintainer release documentation live in the unit model?

- **A. Recommended**: Release packaging/signing owns release and signing documentation; each updater unit owns platform-specific UI copy and test instructions; integrated validation checks all links and instructions.
- **B. Separate documentation unit**: Create a fourth unit for all docs.
- **C. Mac unit**: Put all public and maintainer docs under the Mac distribution work.
- **D. Android unit**: Put all signing and install docs under Android work.
- **E. Other**: Define ownership.

[Answer]: A - Unit 1 owns release docs; platform units own UI copy and platform test instructions.

### Q5. Deployment boundary

Should any unit become an independently deployed service?

- **A. Recommended**: No. Keep all three as modules/work units in the existing monorepo; GitHub Releases is the distribution host and no update backend is introduced.
- **B. Add update service**: Deploy a hosted metadata proxy.
- **C. Split release tooling repository**: Move packaging into another repository.
- **D. Other**: Describe the deployment boundary.

[Answer]: A - keep all units in the monorepo with no hosted update service.

## Proposed requirement allocation

### Unit 1: Release packaging and signing

- FR-01 through FR-05.
- FR-08 and FR-09.
- NFR-01 release-pipeline controls, NFR-02 publication atomicity, NFR-04 package compatibility, and NFR-05 centralized tooling.
- Acceptance criteria 1 through 5 and 9, with physical clean-device checks completed in integrated validation.

### Unit 2: macOS update client

- FR-06.
- Mac portions of FR-03, FR-05, and FR-08.
- NFR-01 artifact verification, NFR-02 update failure safety, NFR-03 Mac update usability, NFR-04 macOS compatibility, and NFR-05 native implementation.
- Acceptance criteria 6 through 8 for macOS.

### Unit 3: Android update client

- FR-07.
- Android portions of FR-04, FR-05, and FR-08.
- NFR-01 checksum/signer verification, NFR-02 update cleanup, NFR-03 Android consent UX, NFR-04 Android compatibility, and NFR-05 native implementation.
- Acceptance criteria 5 through 8 for Android.

## Boundary rules

- Unit 1 owns the language-neutral release contract and CI production path.
- Units 2 and 3 may not diverge from the approved manifest schema or version ordering.
- Unit 2 contains no Android APIs. Unit 3 contains no AppKit or SwiftUI code.
- No unit changes the device-link protocol.
- No unit rewrites Git history, creates branches, or force-pushes `main`.
- Publication happens only after all units and integrated checks pass.

## Security compliance

- Unit 1 owns SECURITY-06, SECURITY-09, SECURITY-10, and SECURITY-12 plus publication aspects of SECURITY-13 and SECURITY-15.
- Units 2 and 3 own runtime aspects of SECURITY-13 and SECURITY-15.
- Remaining security baseline rules are not applicable for the same reasons recorded in approved Application Design.
