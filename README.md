# mac-apps

Personal Mac and iOS apps, built on a home Mac.

| Folder | What |
|---|---|
| [`snapdrag/`](snapdrag/) | Menu bar screenshot and screen recording app for macOS (`./build.sh`) |
| [`packages/HomeUpdater/`](packages/HomeUpdater/) | Swift package: "Update available" banner for the iOS apps |
| [`.claude/skills/ios-deploy/`](.claude/skills/ios-deploy/) | Claude Code skill, scripts and template that create, build and ship the iOS apps |
| [`nas/app-dist/`](nas/app-dist/) | TrueNAS app that serves iOS builds over the air on the tailnet |

Each app is a folder at the root. iOS apps are generated with XcodeGen from
`project.yml` and shipped with `.claude/skills/ios-deploy/scripts/deploy.sh <folder>`:
the build goes straight onto the phone when it's on the home network and is always
published to the NAS, where the phone can install it over Tailscale from anywhere.
Each iOS app's `deploy.json` lists which devices get it.

Signing team, hostnames, device IDs and keys live only on the Mac in
`~/.config/ios-deploy/` and on the NAS, never in this public repo.
