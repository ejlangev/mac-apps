#!/bin/bash
# Scaffold a new iOS app at the repo root from the ios-deploy template.
#   new-app.sh <folder> "<Display Name>"      e.g. new-app.sh grocery-list "Grocery List"
# The bundle ID is <bundlePrefix>.<folder without dashes>; the app's devices start as
# defaultDevices from ~/.config/ios-deploy/config.json. Then run deploy.sh on the folder.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"
need_config

DIR="${1:-}"; DISPLAY="${2:-}"
[[ "$DIR" =~ ^[a-z][a-z0-9-]{1,40}$ ]] || die 'usage: new-app.sh <folder: lowercase, digits, dashes> "<Display Name>"'
[[ "$DISPLAY" =~ ^[A-Za-z][A-Za-z0-9\ ]{0,40}$ ]] || die "display name: letters, digits and spaces"

ROOT="$(cd "$HERE/../../../.." && pwd)"
DEST="$ROOT/$DIR"
[[ -e "$DEST" ]] && die "$DEST already exists"

PREFIX="$(jget "$CONFIG" bundlePrefix)"
[[ "$PREFIX" =~ ^[a-z][a-z0-9-]*(\.[a-z0-9-]+)+$ ]] || die "set bundlePrefix (like com.example) in $CONFIG"
APP="$(echo "$DISPLAY" | tr -cd '[:alnum:]')"            # target / scheme name
BID="$PREFIX.$(echo "$DIR" | tr -d '-')"
DEVICES_JSON="$(/usr/bin/env python3 -I -c 'import json,sys; print(json.dumps(sys.argv[1].split()))' \
  "$(jget "$CONFIG" defaultDevices)")"

cp -R "$HERE/../template" "$DEST"
mv "$DEST/gitignore" "$DEST/.gitignore"
# Fill placeholders in every text file.
find "$DEST" -type f \( -name '*.swift' -o -name '*.yml' -o -name '*.json' -o -name '*.md' \) -print0 |
  while IFS= read -r -d '' f; do
    /usr/bin/env python3 -I - "$f" "$APP" "$DISPLAY" "$BID" "$PREFIX" "$DEVICES_JSON" <<'PY'
import sys
f, app, display, bid, prefix, devices = sys.argv[1:7]
s = open(f).read()
for k, v in {"__APP__": app, "__DISPLAY__": display, "__BUNDLE_ID__": bid,
             "__PREFIX__": prefix, "__DEVICES__": devices}.items():
    s = s.replace(k, v)
open(f, "w").write(s)
PY
  done

cd "$DEST"
command -v xcodegen >/dev/null && xcodegen generate --quiet
echo "Created $DIR ($BID), scheme $APP, devices $DEVICES_JSON"
echo "Next: $HERE/deploy.sh $DEST"
