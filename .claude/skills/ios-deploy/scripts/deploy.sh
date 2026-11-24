#!/bin/bash
# Build an iOS app, publish it to the NAS for over-the-air installs, and push it
# straight to any of the app's devices that the Mac can reach.
#
#   deploy.sh <app-dir>                 build, publish, direct install
#   deploy.sh <app-dir> --no-install    build and publish only
#   deploy.sh <app-dir> --no-publish    build and direct install only
#
# Reads <app-dir>/deploy.json (public, in git) and ~/.config/ios-deploy/config.json
# (private: team, host, device UDIDs, Tailscale logins). Ends with a RESULT block.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

APP_DIR="${1:-}"; shift || true
[[ -n "$APP_DIR" && -f "$APP_DIR/deploy.json" ]] || die "usage: deploy.sh <app-dir> [--no-install|--no-publish]"
DO_INSTALL=1; DO_PUBLISH=1
for a in "$@"; do
  case "$a" in
    --no-install) DO_INSTALL=0 ;;
    --no-publish) DO_PUBLISH=0 ;;
    *) die "unknown option $a" ;;
  esac
done
need_config
APP_DIR="$(cd "$APP_DIR" && pwd)"
DJ="$APP_DIR/deploy.json"

NAME="$(jget "$DJ" name)"
BID="$(jget "$DJ" bundleId)"
SCHEME="$(jget "$DJ" scheme)"
PROJECT="$(jget "$DJ" project)"
DEVICES="$(jget "$DJ" devices)"
HOST="$(jget "$CONFIG" host)"
SSH_HOST="$(jget "$CONFIG" sshHost)"
TEAM="$(team_id)"

# Everything below ends up in URLs, XML or the NAS's access list: keep it boring.
[[ "$NAME" =~ ^[A-Za-z0-9][A-Za-z0-9\ ]{0,40}$ ]] || die "deploy.json name must be letters, digits and spaces"
[[ "$BID" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{2,100}$ ]] || die "deploy.json bundleId looks wrong: $BID"
[[ -n "$SCHEME" && -n "$PROJECT" ]] || die "deploy.json needs scheme and project"
[[ "$HOST" =~ ^[A-Za-z0-9.-]+$ ]] || die "set host (the app-dist ts.net name) in $CONFIG"

BUILD_NUM="$(date +%Y%m%d%H%M)"
OUT="$APP_DIR/build/deploy"
ARCHIVE="$OUT/$SCHEME.xcarchive"
EXPORT="$OUT/export"
rm -rf "$OUT"; mkdir -p "$OUT"

cd "$APP_DIR"
if [[ -f project.yml ]]; then
  command -v xcodegen >/dev/null || die "xcodegen missing: brew install xcodegen"
  say "xcodegen generate"
  xcodegen generate --quiet
fi

say "archive $NAME build $BUILD_NUM (team $TEAM)"
xcodebuild archive -quiet \
  -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
  CURRENT_PROJECT_VERSION="$BUILD_NUM" APP_DIST_HOST="$HOST"

cat >"$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>debugging</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM</string>
  <key>compileBitcode</key><false/>
  <key>thinning</key><string>&lt;none&gt;</string>
</dict></plist>
PLIST

say "export .ipa"
xcodebuild -exportArchive -quiet -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates
IPAS=("$EXPORT"/*.ipa); IPA="${IPAS[0]}"
[[ -f "$IPA" ]] || die "export produced no .ipa"
VERSION="$(plutil -extract ApplicationProperties.CFBundleShortVersionString raw -o - "$ARCHIVE/Info.plist" 2>/dev/null || echo 1.0)"
INSTALL_URL="itms-services://?action=download-manifest&url=https://$HOST/$BID/manifest.plist"

# ---------------------------------------------------------------- publish (flow 4)
PUBLISHED="no"
if [[ $DO_PUBLISH == 1 ]]; then
  [[ -n "$SSH_HOST" ]] || die "set sshHost in $CONFIG"
  RSYNC="$(rsync_bin)"
  STAGE="$OUT/stage"; mkdir -p "$STAGE"

  # Tailscale logins allowed to download this app, from its device list.
  LOGINS=""
  for d in $DEVICES; do
    l="$(jget "$CONFIG" "devices.$d.login")"
    [[ -z "$l" ]] && { echo "warning: device $d has no login in $CONFIG" >&2; continue; }
    [[ "$l" =~ ^[A-Za-z0-9._%+@-]+$ ]] || die "login for $d has odd characters"
    case " $LOGINS " in *" $l "*) ;; *) LOGINS="$LOGINS $l" ;; esac
  done
  [[ -n "$LOGINS" ]] || die "no Tailscale logins for this app's devices; nobody could install it"

  # fetch REMOTE LOCAL: copy a shared file down; a missing one (rsync exit 23) is empty.
  fetch() {
    local rc=0
    "$RSYNC" -q "$SSH_HOST:$1" "$2" 2>/dev/null || rc=$?
    if [[ $rc == 23 ]]; then : >"$2"; elif [[ $rc != 0 ]]; then die "could not read $1 from the NAS (rsync exit $rc)"; fi
  }
  # put LOCAL-DIR: copy a staged tree into the NAS root; files land atomically (temp name + rename).
  put() { "$RSYNC" -rt --chmod=D755,F644 "$1"/ "$SSH_HOST:"; }

  say "publish to $SSH_HOST"
  fetch acl/acl.txt "$STAGE/acl.txt"
  fetch www/apps.txt "$STAGE/apps.txt"

  /usr/bin/env python3 -I - "$STAGE" "$BID" "$NAME" "$LOGINS" <<'PY'
import html, sys, os
stage, bid, name, logins = sys.argv[1:5]
def upsert(path, key, line):
    rows = [r for r in open(path).read().splitlines() if r.strip() and r.split()[0] != key and r.split("\t")[0] != key]
    rows.append(line)
    rows.sort()
    open(path, "w").write("\n".join(rows) + "\n")
upsert(f"{stage}/acl.txt", bid, f"{bid} {' '.join(logins.split())}")
upsert(f"{stage}/apps.txt", bid, f"{bid}\t{name}")
apps = [r.split("\t", 1) for r in open(f"{stage}/apps.txt").read().splitlines() if "\t" in r]
items = "\n".join(
    f'<li data-bid="{html.escape(b)}" hidden><span>{html.escape(n)}</span> <small></small> <a class="btn">Install</a></li>'
    for b, n in apps)
open(f"{stage}/index.html", "w").write(f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Home apps</title>
<style>
body{{font:17px -apple-system,system-ui,sans-serif;margin:0 auto;max-width:560px;padding:24px 16px;background:#fff;color:#111}}
@media (prefers-color-scheme:dark){{body{{background:#000;color:#eee}}}}
ul{{list-style:none;padding:0}} li{{display:flex;align-items:center;gap:8px;padding:12px 0;border-bottom:1px solid #8884}}
li span{{flex:1;font-weight:600}} small{{opacity:.6}}
.btn{{background:#0a84ff;color:#fff;border-radius:16px;padding:6px 14px;text-decoration:none}}
</style></head><body>
<h1>Home apps</h1><ul>
{items}
</ul><p id="none" hidden>No apps for this device.</p>
<script>
// Each app's files answer 404 to people who aren't on its list, so only show what loads.
const rows=[...document.querySelectorAll('li[data-bid]')];
Promise.all(rows.map(li=>fetch('/'+li.dataset.bid+'/version.json',{{cache:'no-store'}})
  .then(r=>r.ok?r.json():null).catch(()=>null).then(v=>{{
    if(!v)return; li.hidden=false;
    li.querySelector('small').textContent=v.version+' ('+v.build+')';
    li.querySelector('a').href=v.install;}})))
 .then(()=>{{document.getElementById('none').hidden=rows.some(li=>!li.hidden);}});
</script></body></html>
""")
PY

  # Order matters: access list first, then .ipa, then manifest, then version.json
  # (the update banner keys off version.json, so it must land last).
  mkdir -p "$STAGE/1/acl" "$STAGE/2/www/$BID" "$STAGE/3/www/$BID" "$STAGE/4/www/$BID" "$STAGE/5/www"
  cp "$STAGE/acl.txt" "$STAGE/1/acl/acl.txt"
  cp "$IPA" "$STAGE/2/www/$BID/app.ipa"
  cat >"$STAGE/3/www/$BID/manifest.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>items</key><array><dict>
  <key>assets</key><array><dict>
    <key>kind</key><string>software-package</string>
    <key>url</key><string>https://$HOST/$BID/app.ipa?b=$BUILD_NUM</string>
  </dict></array>
  <key>metadata</key><dict>
    <key>bundle-identifier</key><string>$BID</string>
    <key>bundle-version</key><string>$VERSION</string>
    <key>kind</key><string>software</string>
    <key>title</key><string>$NAME</string>
  </dict>
</dict></array></dict></plist>
PLIST
  printf '{"build":"%s","version":"%s","install":"%s"}\n' "$BUILD_NUM" "$VERSION" "$INSTALL_URL" \
    >"$STAGE/4/www/$BID/version.json"
  cp "$STAGE/apps.txt" "$STAGE/index.html" "$STAGE/5/www/"
  for i in 1 2 3 4 5; do put "$STAGE/$i"; done
  PUBLISHED="yes"
fi

# ------------------------------------------------------------ direct install (flow 3)
INSTALLED=""; MISSED=""
if [[ $DO_INSTALL == 1 ]]; then
  APPS=("$ARCHIVE"/Products/Applications/*.app); APPBUNDLE="${APPS[0]}"
  LIST="$OUT/devices.json"
  xcrun devicectl list devices --json-output "$LIST" >/dev/null 2>&1 || : >"$LIST"
  for d in $DEVICES; do
    udid="$(jget "$CONFIG" "devices.$d.udid")"
    if [[ -z "$udid" ]]; then MISSED="$MISSED $d(no-udid)"; continue; fi
    if grep -q "$udid" "$LIST" 2>/dev/null && \
       xcrun devicectl device install app --device "$udid" "$APPBUNDLE" >"$OUT/install-$d.log" 2>&1; then
      INSTALLED="$INSTALLED $d"
    else
      MISSED="$MISSED $d"
    fi
  done
fi

echo
echo "RESULT"
echo "app:        $NAME ($BID)"
echo "version:    $VERSION build $BUILD_NUM"
echo "published:  $PUBLISHED"
echo "installed:  ${INSTALLED:- none}"
echo "not pushed: ${MISSED:- none}"
[[ "$PUBLISHED" == yes ]] && echo "link:       $INSTALL_URL" && echo "page:       https://$HOST/"
exit 0
