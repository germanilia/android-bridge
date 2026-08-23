# Direct distribution packaging unit dependencies

## Dependency matrix

| Unit | Depends on | Provides to dependents | Can begin independently |
|---|---|---|---|
| DDP1 Release packaging and signing | Approved requirements and Application Design | Version rules, manifest schema, asset names, signed package contract, local fixtures | Yes |
| DDP2 macOS update client | Frozen DDP1 contract and fixtures | Mac stable-update behavior and Swift validation evidence | Only design work before contract freeze |
| DDP3 Android update client | Frozen DDP1 contract and fixtures | Android stable-update behavior and Kotlin validation evidence | Only design work before contract freeze |
| Integrated Build and Test | Completed DDP1, DDP2, and DDP3 | Cross-unit validation and release readiness evidence | No |

## Required sequence

1. DDP1 Functional and NFR design fixes the version formula, manifest schema, asset names, trust policy, and test fixtures.
2. DDP1 Code Generation implements local package production and validation before publication.
3. DDP2 and DDP3 Functional/NFR designs consume the frozen contract.
4. DDP2 and DDP3 Code Generation may proceed in parallel because neither depends on the other.
5. Integrated Build and Test validates one coherent artifact set and both clients.
6. Sol performs full-diff review and independent checks.
7. Commit, push, CI observation, and publication occur only after validation.

## Coordination contracts

| Contract | Owner | Consumers | Change rule |
|---|---|---|---|
| Root semantic version | DDP1 | Mac bundle, Android Gradle, workflow, both clients | One strict value; stable tag must match |
| Android version-code formula | DDP1 | Gradle, manifest generator, Android updater | Numeric ordering must remain monotonic |
| Release manifest schema | DDP1 | Swift and Kotlin decoders | Schema version change requires both client updates |
| Stable asset names | DDP1 | GitHub workflow, README, both clients | Manifest and Release assets must match exactly |
| Rolling asset names | DDP1 | GitHub workflow, README advanced links | Predictable and replaced as one set |
| SHA-256 format | DDP1 | Both clients | Lowercase 64-character hexadecimal |
| Android signer fingerprint | DDP1 | Android verifier | SHA-256 of the release signing certificate |
| GitHub repository identity | DDP1 | Both clients | Fixed to `germanilia/android-bridge` |

## Cross-unit failure rules

- If DDP1 cannot produce a valid contract fixture, DDP2 and DDP3 code generation is blocked.
- If either runtime decoder disagrees with the generated manifest, publication is blocked.
- If Android signing secrets are absent or signer continuity cannot be proven, Android release publication is blocked.
- If the Mac bundle's stable code requirement changes unexpectedly, publication is blocked to protect privacy grants.
- If SBOM or vulnerability checks fail under the approved policy, stable publication is blocked.
- A rolling release failure must leave the previously complete rolling release available rather than upload a partial new set.

## Ownership boundaries

- DDP1 does not implement runtime UI.
- DDP2 does not configure Android signing or package installation.
- DDP3 does not package or replace the Mac application.
- DDP2 and DDP3 do not modify the manifest schema independently.
- All units preserve the device-link protocol and unrelated repository work.
- Git history rewrite, branch recreation, and force-pushing `main` are outside every unit.

## Security rule allocation

| Rule | DDP1 | DDP2 | DDP3 |
|---|---|---|---|
| SECURITY-06 least privilege | Primary owner | N/A | N/A |
| SECURITY-09 supported stack | Primary owner | Consumer | Consumer |
| SECURITY-10 supply chain | Primary owner | Lock/dependency consumer | Lock/dependency consumer |
| SECURITY-12 secrets | Primary owner | No secrets | No secrets |
| SECURITY-13 artifact integrity | Producer | DMG verifier | APK and signer verifier |
| SECURITY-15 fail closed | Publication | Mac update path | Android update path |

All other security baseline rules remain not applicable because no service, database, authentication system, or cloud network is added.
