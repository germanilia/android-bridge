# Homeserver relay operations

The deployment script configures Nginx Proxy Manager to route the homeserver's trusted Tailscale MagicDNS HTTPS name to `android-bridge-relay:8080` over `system_default`, including WebSocket upgrades. It renews the Tailscale certificate during deployment. Do not publish a host port. Use the Mac and Android root endpoints printed by the script; clients append their own API paths.

The named volume `android_bridge_relay_config` contains only setup state, workspace IDs, device IDs, pair mappings, invitation hashes, and credential hashes. The relay never stores forwarded frames.

## Backup

Stop the container before copying configuration:

```sh
docker compose down
docker run --rm -v android_bridge_relay_config:/config:ro -v "$PWD":/backup alpine:3.21.3 tar czf /backup/relay-config.tar.gz -C /config .
docker compose up -d
```

Keep the archive private. Restore it into an empty `android_bridge_relay_config` volume before starting the service.

## Upgrade and rollback

Keep the previous image tar until the new container reports healthy. Deploy the new image and Compose file with `scripts/deploy-homeserver.sh`. To roll back, load the previous tar, restore its prior image tag in `docker-compose.yml`, and run `docker compose up -d`. Configuration schema version 1 is backward compatible within RELAY2.

Deleting the named volume revokes all enrollment state. Use `--clean-volume` only when intentionally resetting every device credential.
