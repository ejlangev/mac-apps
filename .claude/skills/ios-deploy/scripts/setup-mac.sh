#!/bin/bash
# One-time Mac setup for the ios-deploy pipeline. Safe to run again.
#   - installs xcodegen and rsync with Homebrew
#   - creates ~/.config/ios-deploy/config.json (private; never commit it)
#   - creates the NAS deploy key ~/.ssh/app-dist-deploy and an "app-dist-nas" ssh alias
#   - lists paired devices so you can copy UDIDs into the config
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

command -v brew >/dev/null || die "Homebrew is needed: https://brew.sh"
for p in xcodegen rsync; do
  brew list --formula "$p" >/dev/null 2>&1 || brew install "$p"
done

mkdir -p "$CONFIG_DIR"; chmod 700 "$CONFIG_DIR"
if [[ ! -f "$CONFIG" ]]; then
  cat >"$CONFIG" <<'JSON'
{
  "bundlePrefix": "com.ejlangev",
  "host": "app-dist.YOUR-TAILNET.ts.net",
  "sshHost": "app-dist-nas",
  "defaultDevices": ["ethan-iphone"],
  "devices": {
    "ethan-iphone": { "udid": "PASTE-UDID", "login": "YOUR-TAILSCALE-LOGIN" }
  }
}
JSON
  chmod 600 "$CONFIG"
  echo "Wrote $CONFIG: fill in host, udid and login."
fi

KEY="$HOME/.ssh/app-dist-deploy"
if [[ ! -f "$KEY" ]]; then
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
  ssh-keygen -q -t ed25519 -N '' -C "app-dist-deploy" -f "$KEY"
fi
if ! grep -q '^Host app-dist-nas$' "$HOME/.ssh/config" 2>/dev/null; then
  NAS="$(ssh -G truenas 2>/dev/null | awk '/^hostname /{print $2}')"
  cat >>"$HOME/.ssh/config" <<EOF

Host app-dist-nas
  HostName ${NAS:-10.10.0.10}
  User deploy
  IdentityFile $KEY
  IdentitiesOnly yes
EOF
  echo "Added ssh alias app-dist-nas -> ${NAS:-10.10.0.10}"
fi

echo
echo "Deploy public key (goes on the NAS deploy user, behind rrsync):"
cat "$KEY.pub"
echo
echo "Paired devices (name, UDID):"
TMP="$(mktemp)"
if xcrun devicectl list devices --json-output "$TMP" >/dev/null 2>&1; then
  /usr/bin/env python3 -I - "$TMP" <<'PY'
import json, sys
devs = json.load(open(sys.argv[1])).get("result", {}).get("devices", [])
for d in devs:
    print("  %-30s %s" % (d.get("deviceProperties", {}).get("name", "?"),
                          d.get("hardwareProperties", {}).get("udid", "?")))
if not devs:
    print("  none yet: pair the iPhone in Xcode > Window > Devices and Simulators")
PY
fi
rm -f "$TMP"
