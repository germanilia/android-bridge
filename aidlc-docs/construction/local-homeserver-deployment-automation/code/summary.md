# Local homeserver deployment automation summary

## Delivered

- `scripts/update-local-apps.sh` now updates the Mac, optionally updates one authorized Android phone, and deploys the relay.
- Android absence or ambiguity skips only Android. Relay deployment still runs.
- `.githooks/pre-push` continues to invoke the routine only for pushes targeting remote `main`.
- Relay deployment preserves `android_bridge_relay_config` and existing enrollment state.
- `relay/scripts/deploy-homeserver.sh` now obtains the homeserver's Tailscale MagicDNS name, renews its trusted certificate, installs an idempotent managed HTTPS/WebSocket server block in Nginx Proxy Manager, validates Nginx, and reloads it with rollback on failure.
- The relay remains unexposed on host ports and runs non-root with a read-only root filesystem and dropped capabilities.

## Verification

- Fake-command push/update integration tests passed for non-main pushes, missing ADB, one phone, ambiguous phones, and explicit `ANDROID_SERIAL` selection.
- Bash syntax and ShellCheck passed.
- Ktor relay tests passed.
- Multi-architecture Docker build completed for the homeserver's `linux/amd64` platform.
- Two deployments completed without deleting the named configuration volume.
- `android-bridge-relay` reports healthy.
- Nginx configuration validation passed and contains one managed relay block.
- Trusted HTTPS health check returned HTTP 200 through the generated Tailscale MagicDNS endpoint.
- WebSocket upgrade reached `/v1/connect` through the same trusted endpoint.

## Remaining physical-device work

The Android phone disconnected before a device-side MagicDNS probe. The endpoint uses Tailscale MagicDNS and is ready for enrollment when the phone is connected to the same tailnet.

## Security compliance

SECURITY-01, SECURITY-03, SECURITY-05, SECURITY-07 through SECURITY-10, SECURITY-12, SECURITY-13, and SECURITY-15 are compliant. Other security rules are not applicable to this local deployment-script change. No blocking findings remain.

## Property-based testing compliance

No new transform, parser, serializer, or business invariant was introduced. Partial-mode PBT rules are not applicable. Existing protocol PBT remains unchanged.
