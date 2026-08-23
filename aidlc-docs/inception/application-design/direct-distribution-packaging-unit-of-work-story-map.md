# Direct distribution packaging requirement-to-unit map

No separate user-story stage was needed. This map treats the approved installation and update journeys, functional requirements, NFRs, and acceptance criteria as the complete scope source.

## User journeys

| Journey | Primary unit | Supporting unit | Outcome |
|---|---|---|---|
| New Mac user installs without terminal | DDP1 | Integrated validation | Download DMG, drag app to Applications, Control-click then Open |
| Optional Android user installs directly | DDP1 | Integrated validation | Download release-signed APK and approve Android installation |
| Mac user receives update | DDP2 | DDP1 | Stable check, consent, verified DMG, native open guidance |
| Android user receives update | DDP3 | DDP1 | Stable check, consent, verified same-signer APK, system installer |
| Maintainer publishes stable release | DDP1 | DDP2, DDP3, integrated validation | Matching semantic tag creates complete versioned artifact set |
| Maintainer updates rolling release | DDP1 | Integrated validation | Main push replaces complete predictable latest artifact set |
| Maintainer restores signing setup | DDP1 | None | Documented key backup and secret restoration preserve upgrade continuity |

## Functional requirement map

| Requirement | Owner | Verification focus |
|---|---|---|
| FR-01 Stable and rolling channels | DDP1 | Event selection, shared build path, draft/prerelease exclusion |
| FR-02 macOS DMG packaging | DDP1 | Apple Silicon app, signature, mount, copied-app validation |
| FR-03 macOS direct installation | DDP1 | DMG-first docs, Gatekeeper-safe instructions |
| FR-04 Android release APK | DDP1 | Release signing configuration, missing-secret failure, APK signature |
| FR-05 Version metadata | DDP1 | Root version, tag equality, bundle/Gradle consistency, version code |
| FR-06 macOS update check | DDP2 | Async discovery, consent, checksum, open, errors, retry |
| FR-07 Android update check | DDP3 | Async discovery, consent, checksum, signer, installer, cleanup |
| FR-08 Artifact integrity and contents | DDP1 | DMG/APK checksums, SBOMs, release manifest and notes |
| FR-09 Repository setup docs | DDP1 | Secret names, key lifecycle, Mac identity, release procedure |

## NFR map

| NFR | DDP1 | DDP2 | DDP3 |
|---|---|---|---|
| NFR-01 Security | Secrets, action pins, SBOM, scans, signed artifacts | HTTPS and DMG integrity | HTTPS, APK integrity, signer continuity |
| NFR-02 Reliability | Publish only complete validated sets | Preserve installed app and clean temporary DMG data | Preserve installed app and clean APK cache |
| NFR-03 Usability | Direct links and installation guidance | Native consent and actionable errors | Native consent, system installer, actionable errors |
| NFR-04 Compatibility | macOS 13 arm64 and Android 13+ packages | Bundle version and existing Mac data untouched | Version code, signer continuity, Android data untouched |
| NFR-05 Maintainability | Central contract and native release tools | Foundation/AppKit/SwiftUI only | Kotlin/Android/Gradle/Compose only |

## Acceptance-criteria map

| Criterion | Primary owner | Integrated evidence |
|---|---|---|
| AC-01 Tagged stable artifact set | DDP1 | Successful tagged CI run and Release inspection |
| AC-02 Rolling artifact set | DDP1 | Successful `main` CI run and `latest-build` inspection |
| AC-03 Clean Mac DMG install | DDP1 | Apple Silicon clean-user installation checklist |
| AC-04 Android 13+ direct install | DDP1 | Physical-device unknown-source installation checklist |
| AC-05 Same-key Android upgrade | DDP1 and DDP3 | Two sequential release APKs installed without uninstall |
| AC-06 Both apps detect newer stable release | DDP2 and DDP3 | Controlled metadata fixtures plus published release test |
| AC-07 Verify before native handoff | DDP2 and DDP3 | Tampered DMG/APK tests prove open/installer is not invoked |
| AC-08 Invalid input preserves installation | All units | Version, metadata, checksum, signer, and missing-secret negative tests |
| AC-09 Maintainer can configure and publish | DDP1 | Release guide walkthrough without committed secrets |

## Test ownership

### DDP1

- Version parser and version-code derivation examples.
- Manifest generation and validation fixtures.
- Shell syntax and package-script checks.
- Gradle release-signing configuration checks.
- DMG mount, architecture, and signature validation.
- APK signature and checksum validation.
- Workflow event, permissions, action-pin, artifact-set, SBOM, and scan checks.
- README and maintainer-guide link/content checks.

### DDP2

- Swift semantic ordering and malformed input tests.
- Stable release and asset selection tests.
- Manifest schema, tag, host, size, and hash rejection tests.
- Current/equal/newer version decision tests.
- Download success, oversize, checksum mismatch, cancellation, and cleanup tests.
- Controller/UI orchestration checks where testable without opening an actual DMG.

### DDP3

- Kotlin semantic ordering and malformed input tests.
- Stable release and asset selection tests.
- Manifest schema, tag, host, size, hash, and signer metadata rejection tests.
- Current/equal/newer version decision tests.
- Download, checksum, signer continuity, cleanup, and installer-gating tests.
- Physical Android 13+ direct install and same-key upgrade instructions.

## Coverage conclusion

- Every FR has one primary owner.
- Every NFR has an explicit cross-unit allocation.
- Every acceptance criterion has an owner and integrated evidence path.
- No requirement is assigned to a new hosted service or marketplace.
- No mapped work permits silent installation, notarization claims, protocol changes, or Git history rewriting.
