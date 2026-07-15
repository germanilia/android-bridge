# Mobile Second Brain Sync Resiliency Questions

You enabled the Resiliency Baseline. Please answer each question by filling the letter after `[Answer]:`.

## Question 1: RTO/RPO Goals and Disaster Recovery Strategy
For this local Mac/Android Second Brain sync feature, what recovery target should apply?

A) RPO/RTO: Hours — acceptable for personal/local feature; recover from Mac Second Brain files and Android local queue/cache

B) RPO/RTO: 10s of minutes — queued mobile edits should recover quickly after app/device restart

C) RPO/RTO: Minutes — stronger local durability and automatic recovery needed

D) Near real-time — no meaningful data loss acceptable after local device/app failure

E) N/A — no formal DR target; best-effort personal local sync is acceptable

X) Other (please describe after [Answer]: tag below)

[Answer]: E

## Question 2: Change Management Process
How should production changes for this local app feature be governed?

A) Use existing project process: GitHub PR/review + CI checks + release artifacts

B) No formal process exists — use lightweight change record + rollback note in AI-DLC docs

C) N/A — personal/internal feature exempt from formal change management

X) Other (describe after [Answer]: tag below)

[Answer]: A

## Question 3: CI/CD and Deployment Tooling
What CI/CD tooling and deployment process should this feature use?

A) Use existing GitHub Actions pipeline and current Mac/APK artifact publishing

B) No pipeline needed for this increment; local build/test only

X) Other (describe after [Answer]: tag below)

[Answer]: A

## Question 4: Rollback Mechanism
How should a failed release be rolled back?

A) Redeploy previous Mac app/APK artifact version

B) Disable Second Brain sync via feature toggle/settings until fixed

C) Both previous artifact rollback and feature disable path

D) Data-aware rollback required for node changes/conflicts

X) Other (describe after [Answer]: tag below)

[Answer]: C

## Question 5: Deployment Style
What deployment strategy is acceptable?

A) Direct install/update from latest artifacts

B) Manual staged rollout: install on your devices first, then publish

C) Canary/beta release artifact before stable latest-build

X) Other (describe after [Answer]: tag below)

[Answer]: A

## Question 6: Regional Topology
Does this workload require regional/cloud redundancy?

A) N/A — local peer-to-peer app; no cloud region topology

B) Single cloud region later if cloud backup/indexing is added

C) Multi-region is required later

X) Other (describe after [Answer]: tag below)

[Answer]: A

## Question 7: Incident Response Process
How are incidents handled for this feature?

A) Use GitHub issues plus local logs/screenshots for triage

B) Lightweight personal process: record issue in AI-DLC audit/notes, fix, add regression test

C) Existing formal incident process

X) Other (describe after [Answer]: tag below)

[Answer]: A

## Question 8: Resiliency Testing Approach
How will sync resiliency be validated?

A) Automated tests for offline queue, reconnect replay, idempotency, conflict handling; manual device test for real connectivity

B) Manual testing only

C) Defer resiliency testing to Operations

X) Other (describe after [Answer]: tag below)

[Answer]: A
