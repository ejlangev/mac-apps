# HomeUpdater

Swift package used by the iOS apps in this repo. Add `.homeUpdater()` to an app's root
view and it shows an "Update available" banner when the home app server has a newer build.
Tapping Install opens the `itms-services://` link; iOS asks to confirm, so there are no
silent updates.

It reads two Info.plist values:

- `HomeUpdaterHost`: the app server's `ts.net` name (deploy.sh fills it at build time
  from `~/.config/ios-deploy/config.json`; empty disables the check).
- `CFBundleVersion`: compared with `build` in `https://<host>/<bundle-id>/version.json`.

It checks on launch and on every return to the foreground, at most once a minute. Any
failure is silent.
