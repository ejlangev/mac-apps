# __DISPLAY__

iOS app, bundle ID `__BUNDLE_ID__`. Personal use: it is installed by development
signing on the devices listed in `deploy.json`, never through the App Store.

- Build and ship with the `ios-deploy` skill: `../.claude/skills/ios-deploy/scripts/deploy.sh .`
  Do this after every change you want on the phone, then relay the RESULT block.
- Change the project in `project.yml` (XcodeGen). Never hand-edit the `.xcodeproj`; it is generated and gitignored.
- Keep `.homeUpdater()` on the root view: it is how the installed app learns a new build exists.
- `devices` in `deploy.json` are names from the private `~/.config/ios-deploy/config.json`.
  Never put UDIDs, emails, team IDs or hostnames in this folder: the repo is public.
