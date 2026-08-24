# Local homeserver deployment automation requirements

## Intent

Deploy the existing Android Bridge relay to the private homeserver and include relay deployment in the repository's existing `main` pre-push local update routine.

## Requirements

1. A push targeting remote `main` must run the existing Mac update, update one selected authorized Android device when available, and deploy the relay to `homeserver`.
2. Relay deployment must still run when Android tooling or an authorized phone is unavailable.
3. Mac build/install, selected Android build/install, or relay deployment failures must stop the push.
4. Non-`main` pushes and deletion of remote `main` must not run local deployment.
5. Relay deployment must preserve the named configuration volume and existing enrollment state. Automation must never use `--clean-volume`.
6. Deployment must keep the relay private behind Nginx Proxy Manager on `system_default`, with no host port mapping.
7. No setup code, device credential, or other secret may enter Git or test logs.
8. Tests must prove relay invocation for the supported Android availability cases and prove non-`main` pushes remain no-ops.
9. Documentation must state that Git has a pre-push hook rather than a post-push hook, so local updates and relay deployment complete before Git sends `main`.
10. The initial deployment must report a healthy relay container. NPM, tailnet DNS, WebSockets, and trusted TLS remain required before app enrollment.

## Scope

Modified components:

- `.githooks/pre-push`
- `scripts/update-local-apps.sh`
- `scripts/test-update-local-apps.sh`
- relay homeserver deployment and operator documentation

No relay protocol, persistence schema, app enrollment flow, or public release behavior changes.

## Security compliance

- SECURITY-01: Compliant. Client access remains TLS-only; NPM terminates trusted TLS.
- SECURITY-03: Compliant. Existing relay audit logging remains active and excludes credentials and payloads.
- SECURITY-05: Compliant. Existing bounded relay request and frame validation is unchanged.
- SECURITY-07: Compliant. No host port is published; only NPM's `system_default` network reaches the container.
- SECURITY-08: Compliant. Existing authenticated pair isolation remains unchanged.
- SECURITY-09: Compliant. Non-root, read-only, capability-dropped container configuration remains unchanged.
- SECURITY-10: Compliant. Docker bases and dependencies remain pinned.
- SECURITY-12: Compliant. Setup codes stay in the untracked remote `.env`; credentials remain hashed.
- SECURITY-13: Compliant. The deployment builds the reviewed local source and ships a self-contained image over SSH.
- SECURITY-15: Compliant. Deployment and hook failures stop the operation.
- Other security rules: N/A to this local deployment-script change.

## Property-based testing compliance

No new serialization, transformation, parser, or business invariant is introduced. PBT-02, PBT-03, PBT-07, PBT-08, and PBT-09 are N/A. Existing protocol PBT remains unchanged.
