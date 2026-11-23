# mac-apps

Public repo of personal apps. One folder per app at the root.

- iOS apps: use the `ios-deploy` skill (`.claude/skills/ios-deploy/SKILL.md`) to create,
  build and ship them. Edit `project.yml`, never a generated `.xcodeproj`.
- `snapdrag/` is a macOS app with a hand-made Xcode project and its own `build.sh`;
  leave its layout alone.
- Never commit secrets or personal identifiers: Apple team IDs, device UDIDs, Tailscale
  logins or hostnames, emails, SSH keys. Those live in `~/.config/ios-deploy/` on the Mac.
