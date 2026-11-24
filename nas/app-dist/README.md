# app-dist: the NAS side of the iOS app pipeline

Serves each app's `.ipa`, `manifest.plist` and `version.json` to iPhones on the
tailnet, so apps can be installed and updated over the air from anywhere.

```
Mac    --rsync over ssh (deploy user, rrsync)-->  /mnt/tank/app-dist/pub/{www,acl}
iPhone --tailnet HTTPS--> tailscale serve (app-dist.<tailnet>.ts.net) --> Caddy :8080 --> /srv (www, read-only)
```

Nothing secret lives in this folder. The Tailscale auth key, the Mac's public key,
Tailscale logins and device UDIDs stay on the box or the Mac.

## Layout on the box

| Path | What | Owner |
|---|---|---|
| `tank/app-dist` dataset (`/mnt/tank/app-dist`) | builds | root |
| `/mnt/tank/app-dist/home/deploy` | deploy user's home (authorized_keys) | deploy |
| `/mnt/tank/app-dist/pub/www/<bundle-id>/` | `app.ipa`, `manifest.plist`, `version.json` | deploy |
| `/mnt/tank/app-dist/pub/www/index.html`, `apps.txt` | install page for a new or reset phone | deploy |
| `/mnt/tank/app-dist/pub/acl/acl.txt` | `<bundle-id> <tailscale-login> ...` per app | deploy |
| `/mnt/apps/app-dist/config/` | `Caddyfile`, `caddy-start.sh`, `serve.json` from this folder | root |
| `/mnt/apps/app-dist/tailscale/` | Tailscale node state | root |
| `/mnt/apps/app-dist/secrets/ts-authkey` | one-time tagged auth key (mode 600) | root |
| `/mnt/apps/app-dist/.nobackup` | keeps node keys out of the S3 backup | root |

The home directory sits outside `pub/` on purpose: rrsync confines the deploy key to
`pub/`, so it can never rewrite its own `authorized_keys`.

## Deploy user

- Created with `midclt call user.create` (so it survives upgrades): username `deploy`,
  own group, home `/mnt/tank/app-dist/home/deploy`, shell `/usr/bin/bash` (a forced
  command needs a real shell), password disabled, no sudo, no SMB.
- Its only SSH key is the Mac's `~/.ssh/app-dist-deploy.pub`, with a forced command:

  ```
  command="/usr/bin/rrsync -no-del /mnt/tank/app-dist/pub",restrict ssh-ed25519 AAAA... app-dist-deploy
  ```

  `rrsync` ships with rsync 3.2.4+. If it's missing from TrueNAS, put a copy under
  `/mnt/apps/app-dist/bin/` and point the command there.

## Access control, two layers

1. **Tailscale policy** (admin console): only listed people can reach the node at all.
   ```jsonc
   "tagOwners": { "tag:app-dist": ["autogroup:admin"] },
   "groups":    { "group:app-dist": ["<your tailscale login>"] },
   "grants": [
     { "src": ["group:app-dist"], "dst": ["tag:app-dist"], "ip": ["tcp:443"] }
   ]
   ```
   If the policy still has the default allow-all rule, this grant changes nothing until
   that rule is narrowed. MagicDNS and HTTPS certificates must be on.
2. **Per app** (Caddy): `tailscale serve` adds `Tailscale-User-Login` to every request.
   `caddy-start.sh` turns `acl.txt` into rules so each app's files answer 404 unless the
   login is on that app's list. `deploy.sh` writes the list from the app's `devices` in
   `deploy.json` and the logins in the Mac's private config. To give someone an app, add
   their device to the private config and to that app's `devices`, then deploy.

The installer can't send tokens, so Tailscale identity is the only auth. App names
(`apps.txt`) are visible to anyone who can reach the node; the builds are not.

## First-time setup (box)

1. Create `tank/app-dist` and the directories above; create the deploy user.
2. Copy `Caddyfile`, `caddy-start.sh` and `serve.json` to `/mnt/apps/app-dist/config/`.
3. Put a one-time, pre-approved auth key tagged `tag:app-dist` in
   `/mnt/apps/app-dist/secrets/ts-authkey` (600). Delete it after the node logs in.
4. Create the custom app from `compose.yaml` (`midclt call -j app.create` with
   `custom_app: true`, `app_name: app-dist`, `custom_compose_config_string`).
5. Check: `docker exec <caddy> caddy validate --config /config/Caddyfile --adapter caddyfile`,
   then from a tailnet device `curl -I https://app-dist.<tailnet>.ts.net/`.

Both images use `:latest`, so the weekly app-upgrade routine keeps them current.
