#!/bin/sh
# Entrypoint for the app-dist Caddy container. Turns /acl/acl.txt (written by the Mac's
# deploy.sh, one line per app: "<bundle-id> <tailscale-login> ...") into Caddy rules,
# starts Caddy, and reloads it whenever acl.txt changes. acl.txt is data only: lines
# that don't match the strict patterns below are skipped, so the deploy user can't
# inject Caddy config.
set -eu
set -f   # no globbing when splitting lines
ACL=/acl/acl.txt
OUT=/tmp/acl
CONF=/config/Caddyfile
mkdir -p "$OUT"

gen() {
  tmp="$OUT/acl.caddy.tmp"
  : >"$tmp"
  n=0
  if [ -f "$ACL" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      # shellcheck disable=SC2086
      set -- $line
      [ $# -ge 1 ] || continue
      bid=$1; shift
      if ! printf '%s\n' "$bid" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9.-]{2,100}$'; then
        echo "acl: skipping bad bundle id line" >&2; continue
      fi
      ok=1
      for l in "$@"; do
        printf '%s\n' "$l" | grep -Eq '^[A-Za-z0-9._%+@-]{1,200}$' || ok=0
      done
      [ $ok = 1 ] || { echo "acl: skipping $bid (bad login)" >&2; continue; }
      n=$((n + 1))
      {
        echo "@deny$n {"
        echo "	path /$bid /$bid/*"
        if [ $# -gt 0 ]; then
          echo "	not {"
          for l in "$@"; do echo "		header Tailscale-User-Login $l"; done
          echo "	}"
        fi
        echo "}"
        echo "respond @deny$n 404"
      } >>"$tmp"
    done <"$ACL"
  fi
  mv "$tmp" "$OUT/acl.caddy"
  echo "acl: $n app rules"
}

sum() { cksum "$ACL" 2>/dev/null || echo none; }

gen
caddy run --config "$CONF" --adapter caddyfile &
pid=$!
trap 'kill "$pid" 2>/dev/null; exit 0' TERM INT
last=$(sum)
while kill -0 "$pid" 2>/dev/null; do
  sleep 10 & wait $!
  now=$(sum)
  if [ "$now" != "$last" ]; then
    last=$now
    gen && caddy reload --config "$CONF" --adapter caddyfile || echo "acl: reload failed, keeping old rules" >&2
  fi
done
exit 1
