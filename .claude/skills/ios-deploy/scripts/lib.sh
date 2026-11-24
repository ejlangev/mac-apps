# Shared helpers for the ios-deploy scripts. Source it; don't run it.
# Works with the bash 3.2 that ships with macOS.

CONFIG_DIR="${IOS_DEPLOY_CONFIG_DIR:-$HOME/.config/ios-deploy}"
CONFIG="$CONFIG_DIR/config.json"

die() { echo "error: $*" >&2; exit 1; }
say() { echo "==> $*"; }

# jget FILE KEY.PATH  -> prints the value ("" when missing). Arrays print one item per line.
jget() {
  /usr/bin/env python3 -I - "$1" "$2" <<'PY'
import json, sys
path, keys = sys.argv[1], sys.argv[2]
try:
    v = json.load(open(path))
except FileNotFoundError:
    sys.exit(0)
for k in keys.split("."):
    if isinstance(v, dict) and k in v:
        v = v[k]
    else:
        sys.exit(0)
if isinstance(v, list):
    print("\n".join(str(x) for x in v))
elif isinstance(v, dict):
    print("\n".join(v.keys()))
elif v is not None:
    print(v)
PY
}

need_config() {
  [[ -f "$CONFIG" ]] || die "no $CONFIG. Run .claude/skills/ios-deploy/scripts/setup-mac.sh first."
}

# The Apple developer team: config teamId, then $DEVELOPMENT_TEAM, then the
# "Apple Development" certificate in the keychain (same rule as snapdrag/build.sh).
team_id() {
  local t
  t="${DEVELOPMENT_TEAM:-$(jget "$CONFIG" teamId)}"
  if [[ -z "$t" ]]; then
    t="$(security find-certificate -c "Apple Development" -p 2>/dev/null \
      | openssl x509 -noout -subject -nameopt multiline 2>/dev/null \
      | awk -F'= ' '/organizationalUnitName/ {print $2; exit}')"
  fi
  [[ -n "$t" ]] || die "no Apple developer team. Sign in under Xcode > Settings > Accounts or set teamId in $CONFIG."
  echo "$t"
}

# Homebrew rsync: macOS's own rsync/openrsync can't talk to the NAS's rrsync reliably.
rsync_bin() {
  local r
  for r in /opt/homebrew/bin/rsync /usr/local/bin/rsync; do
    [[ -x "$r" ]] && { echo "$r"; return; }
  done
  die "Homebrew rsync not found. Run: brew install rsync"
}
