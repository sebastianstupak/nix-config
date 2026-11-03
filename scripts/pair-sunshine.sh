#!/usr/bin/env bash
#
# Headless Moonlight pairing from a Linux client — the bash port that
# scripts/pair-sunshine.md invites ("the same flow works with bash + curl +
# ssh"). Read that file first; it explains the protocol and the Windows
# original. This script pairs THIS machine (the client) with a Sunshine host.
#
# Why it exists: the PIN for a pairing must be entered in the web UI of the
# machine being streamed FROM, that UI is localhost-only
# (`origin_web_ui_allowed = "pc"`), and so a host whose admin password you do
# not have is unpairable from anywhere. On 2026-11-03 that blocked
# zagreus -> hestia while hestia -> zagreus went through in one attempt.
#
# THE PASSWORD IS PROMPTED, HIDDEN, EVERY RUN, AND NEVER STORED.
#
# That is deliberate and is the main difference from the PowerShell version,
# which caches a DPAPI blob because Windows has one. The Linux equivalent would
# be an age-encrypted file under the personal key — worth adding if this gets
# run often, but prompting is strictly safer and this is a once-per-pair
# operation. More importantly: pair-sunshine.md states the whole point is that
# no credential touches a shell history or an AI context, so the password must
# not be an argument, must not be an environment variable, and must not appear
# in `ps`. It is passed to curl through `--config -` on stdin for that reason;
# `-u user:pass` would expose it in the process table to every local user.
#
# Usage:
#   pair-sunshine.sh <host-fqdn> [--name <label>] [--user <admin-user>]
#
#   pair-sunshine.sh hestia.netbird.cloud
#   pair-sunshine.sh hestia.netbird.cloud --name zagreus
#
# If you do not know the host's admin password, set a fresh one over SSH — no
# old password required (from pair-sunshine.md):
#   ssh <host> 'systemctl --user stop sunshine; sunshine --creds <user> <pass>; systemctl --user start sunshine'
# Then record it per host, as secrets/README.md now says to.
set -euo pipefail

host=""
name="$(hostname)"
admin_user="sebastianstupak"

while [ $# -gt 0 ]; do
  case "$1" in
    --name) name="${2:?--name needs a value}"; shift 2 ;;
    --user) admin_user="${2:?--user needs a value}"; shift 2 ;;
    -h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) host="$1"; shift ;;
  esac
done

[ -n "$host" ] || { echo "usage: $(basename "$0") <host-fqdn> [--name <label>] [--user <admin-user>]" >&2; exit 2; }

for t in ssh curl python3 moonlight; do
  command -v "$t" >/dev/null 2>&1 || { echo "missing required tool: $t" >&2; exit 1; }
done

# Qt has no display when this runs over SSH or from a bare shell; Moonlight's
# CLI does not need one, but it refuses to start without a platform plugin.
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"

workdir="$(mktemp -d)"
ctl="$workdir/ssh-ctl"
curlcfg="$workdir/curl.cfg"
body="$workdir/body.json"
pairlog="$workdir/moonlight-pair.log"
cleanup() {
  [ -S "$ctl" ] && ssh -S "$ctl" -O exit "$host" 2>/dev/null || true
  rm -rf "$workdir"
}
trap cleanup EXIT
chmod 700 "$workdir"

# A high, unlikely-to-collide local port; the tunnel is torn down on exit.
port=$((20000 + RANDOM % 20000))

echo "Opening SSH tunnel: localhost:$port -> $host:47990"
ssh -M -S "$ctl" -f -N -o BatchMode=yes -o ExitOnForwardFailure=yes \
  -L "$port:localhost:47990" "$admin_user@$host"

probe="$(curl -k -s -o /dev/null -w '%{http_code}' --max-time 15 "https://localhost:$port/" || true)"
case "$probe" in
  200|302|401) echo "Sunshine web UI reachable through the tunnel (HTTP $probe)" ;;
  *) echo "Sunshine web UI not responding through the tunnel (got '$probe')." >&2; exit 1 ;;
esac

# --- the one interactive step ----------------------------------------------
printf 'Sunshine admin password for %s (hidden): ' "$host" >&2
read -rs password
printf '\n' >&2
[ -n "$password" ] || { echo "empty password; aborting." >&2; exit 1; }

# curl reads credentials from this file, so they never reach the process table.
umask 077
printf 'user = "%s:%s"\ninsecure\nsilent\n' "$admin_user" "$password" > "$curlcfg"
unset password

api() { curl -K "$curlcfg" --max-time 20 "$@"; }

before="$(api "https://localhost:$port/api/pin" || true)"
if printf '%s' "$before" | grep -qi 'unauthoriz\|not authorized'; then
  echo "Sunshine rejected the admin password." >&2
  echo "Reset it on the host (no old password needed):" >&2
  echo "  ssh $host 'systemctl --user stop sunshine; sunshine --creds $admin_user <pass>; systemctl --user start sunshine'" >&2
  exit 1
fi

ids() { python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
for p in (d.get("pairings") or []):
    if p.get("id"): print(p["id"])
'; }

before_ids="$(printf '%s' "$before" | ids || true)"

pin="$(printf '%04d' $((RANDOM % 10000)))"
echo "Starting Moonlight pairing with PIN $pin (it is submitted for you)"
moonlight pair "$host" --pin "$pin" >"$pairlog" 2>&1 &
pair_pid=$!

# Poll for the pending pairing Moonlight just created. Sunshine assigns it an
# id we must echo back; posting only {pin} makes it 400 on the missing key.
pairing_id=""
for _ in $(seq 1 30); do
  pending="$(api "https://localhost:$port/api/pin" || true)"
  while read -r candidate; do
    [ -n "$candidate" ] || continue
    if ! printf '%s\n' "$before_ids" | grep -qxF "$candidate"; then
      pairing_id="$candidate"
      break
    fi
  done <<< "$(printf '%s' "$pending" | ids || true)"
  [ -n "$pairing_id" ] && break
  kill -0 "$pair_pid" 2>/dev/null || break
  sleep 1
done

if [ -z "$pairing_id" ]; then
  echo "No new pending pairing appeared — Moonlight may not have initiated." >&2
  echo "Its log:" >&2
  tail -5 "$pairlog" >&2 || true
  exit 1
fi

printf '{"pairing_id":"%s","pin":"%s","name":"%s"}\n' "$pairing_id" "$pin" "$name" > "$body"
resp="$(api -H 'Content-Type: application/json' -X POST --data-binary "@$body" \
  "https://localhost:$port/api/pin" || true)"
echo "Sunshine /api/pin response: $resp"

wait "$pair_pid" 2>/dev/null || true
if grep -qi 'incorrect pin' "$pairlog"; then
  echo "Moonlight reported Incorrect PIN." >&2
  echo "Note that it says this whenever no PIN reached the server, not only on a typo." >&2
  exit 1
fi

# An entry in the host's state file only proves something was written; listing
# apps proves the pairing actually authenticates.
echo "Verifying with moonlight list..."
if moonlight list "$host" 2>/dev/null | grep -vE '^[0-9:]+ - (Qt|SDL)' | grep -q .; then
  echo "PAIRED — $host lists apps for this client."
  moonlight list "$host" 2>/dev/null | grep -vE '^[0-9:]+ - (Qt|SDL)' | sed 's/^/  /'
else
  echo "Could not confirm via 'moonlight list'. If Moonlight shows $host without" >&2
  echo "a lock icon, it is paired regardless." >&2
  exit 1
fi
