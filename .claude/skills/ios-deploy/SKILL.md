---
name: ios-deploy
description: Create, build and ship Ethan's personal iOS apps in this repo to his iPhone (direct install at home, over-the-air link from the NAS otherwise). Use for "make me an app that...", any change to an iOS app here, "deploy", "put it on my phone", or adding a device to an app.
---

# ios-deploy

Personal iOS apps, signed with development signing and installed without the App Store
or TestFlight. Every app is a folder at the repo root with a `deploy.json`.

## Make a new app

1. Pick a short lowercase folder name and a display name.
2. `.claude/skills/ios-deploy/scripts/new-app.sh <folder> "<Display Name>"`
   This copies `template/` (XcodeGen `project.yml`, `deploy.json`, `CLAUDE.md`, a
   SwiftUI starter with `.homeUpdater()` wired in) and fills in the bundle ID and devices.
3. Write the app in `<folder>/Sources/`. Change targets, settings, capabilities and
   Info.plist keys in `project.yml` only; never hand-edit the generated `.xcodeproj`.
4. Deploy (below).

## Deploy (after every change the user wants on a phone)

```
.claude/skills/ios-deploy/scripts/deploy.sh <folder>
```

It regenerates the project, stamps `CFBundleVersion` with a `YYYYMMDDHHMM` timestamp,
archives and exports a signed `.ipa` (export method `debugging`,
`-allowProvisioningUpdates`), publishes it to the NAS, then installs it directly on each
of the app's devices the Mac can reach. It ends with a `RESULT` block. Relay it:

- `installed:` lists devices it was pushed to. Say "Installed on your iPhone".
- Otherwise give the `page:` link (https, opens in Safari on the phone over Tailscale)
  and the `link:` (`itms-services://`) for that app. Apps already on the phone also
  show an "Update available" banner on next open.

Options: `--no-install` (publish only), `--no-publish` (direct install only, e.g. when
the NAS is down).

If a build fails, fix the code and deploy again. If signing fails with an expired
certificate or profile, deploying again with the same command renews them (yearly).
Direct installs work best with the phone unlocked; after a phone reboot, unlock it once.

## Devices and who gets which app

- `deploy.json` `devices` holds device **names**. The private
  `~/.config/ios-deploy/config.json` maps each name to its UDID and Tailscale login.
- A device name in an app's `devices` means: direct installs go to that device, and that
  person's Tailscale login may download the app from the NAS. Everyone else gets 404.
- Adding a person's phone: pair it with the Mac once by cable (Xcode, Devices and
  Simulators, trust, Developer Mode on, "Connect via network"), add it to the private
  config with its UDID (from `setup-mac.sh` or `xcrun devicectl list devices`) and their
  Tailscale login, add the name to the app's `devices`, and deploy. The first deploy
  registers the device with Apple (`-allowProvisioningDeviceRegistration`).

## Never

- Never commit UDIDs, Tailscale logins, emails, the team ID, the ts.net hostname, keys
  or anything from `~/.config/ios-deploy/`. This repo is public.
- Never add the App Store, TestFlight or distribution signing.
- Never edit `snapdrag/` as part of this workflow; it's a macOS app with its own `build.sh`.

## One-time Mac setup (for reference)

`.claude/skills/ios-deploy/scripts/setup-mac.sh` installs xcodegen and rsync, creates the
private config and the NAS deploy key, and lists paired devices. Paid Apple Developer
Program membership is required (a free Personal Team's profiles expire in 7 days).

Suggested allowlist so the phone isn't flooded with approvals (the user adds it to
`.claude/settings.local.json` or `~/.claude/settings.json` themselves):

```json
{ "permissions": { "allow": [
  "Bash(xcodebuild:*)", "Bash(xcodegen:*)", "Bash(xcrun devicectl:*)",
  "Bash(.claude/skills/ios-deploy/scripts/deploy.sh:*)",
  "Bash(.claude/skills/ios-deploy/scripts/new-app.sh:*)"
] } }
```

NAS side: see `nas/app-dist/README.md`.
