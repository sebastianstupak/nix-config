#!/usr/bin/env bash
#
# Is the personal age key on THIS machine the one the repo is encrypted to?
#
# `.sops.yaml` is the single source of truth: its `&sebastianstupak` anchor
# names the one human recipient every secret is encrypted to. The private half
# lives in several physical places by design — a Proton Pass secure note plus
# every machine you edit secrets from — and that is precisely the problem this
# script exists for: several copies of one logical key can silently diverge,
# and nothing notices until `sops -d` fails on a file you did not expect.
#
# It has gone wrong twice:
#   2026-11-01  the anchor had drifted from the key actually in use, so every
#               file was encrypted to a recipient that existed nowhere. The
#               machines never noticed (they decrypt with host keys); only the
#               human escape hatch was dead.
#   2026-11-03  zagreus held a THIRD key, created 2026-09-10, that was never a
#               recipient of anything. It looked entirely plausible sitting
#               there at the documented path with the documented permissions.
#
# Both were found by a decryption failing long after the fact. This turns that
# into an immediate, specific error.
#
# NOT a `nix flake check`: the thing being verified lives at
# ~/.config/sops/age/keys.txt, outside the repo and outside the build sandbox,
# so a pure evaluation cannot see it. It runs as a git hook instead — scoped by
# lefthook to commits that touch `secrets/` or `.sops.yaml`, the only times a
# wrong key can do damage.
#
# Pure bash + grep, with age-keygen used only when present, so this behaves on
# a Windows checkout with no Nix exactly as the other hooks do.
#
# Exit codes:  0 = matches, or cannot be checked (missing key/anchor)
#              1 = key present and WRONG — the case worth blocking
#
# Usage: check-age-key.sh            (run from anywhere in the repo)
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
sops_yaml="$repo_root/.sops.yaml"
key_file="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

# --- what the repo expects -------------------------------------------------
# The anchor line looks like:   - &sebastianstupak age1nmnth...
if [ ! -r "$sops_yaml" ]; then
  echo "check-age-key: no .sops.yaml at $sops_yaml — skipping."
  exit 0
fi

expected="$(grep -oE '^[[:space:]]*-[[:space:]]*&sebastianstupak[[:space:]]+age1[a-z0-9]+' "$sops_yaml" |
  grep -oE 'age1[a-z0-9]+' | head -n1 || true)"

if [ -z "$expected" ]; then
  echo "check-age-key: no &sebastianstupak anchor found in .sops.yaml — skipping."
  echo "  If the anchor was renamed, update this script to match; a silent skip"
  echo "  here is how the 2026-11-01 drift went unnoticed for months."
  exit 0
fi

# --- what this machine actually has ---------------------------------------
if [ ! -r "$key_file" ]; then
  # Absence is legitimate: a machine that never edits secrets does not need the
  # key, and it decrypts its own at activation with its host key. Only a WRONG
  # key is a failure.
  echo "check-age-key: no key at $key_file — skipping (nothing to diverge)."
  exit 0
fi

actual=""
if command -v age-keygen >/dev/null 2>&1; then
  # Authoritative: derived from the private half.
  actual="$(age-keygen -y "$key_file" 2>/dev/null || true)"
else
  # Fallback for a checkout with no Nix. age-keygen writes a `# public key:`
  # comment when it creates the file; trust it only because the alternative is
  # no check at all, and say so.
  actual="$(grep -oE '^#[[:space:]]*public key:[[:space:]]*age1[a-z0-9]+' "$key_file" |
    grep -oE 'age1[a-z0-9]+' | head -n1 || true)"
  if [ -n "$actual" ]; then
    echo "check-age-key: age-keygen not on PATH; trusting the file's own"
    echo "  '# public key:' comment, which a hand-edit could have made stale."
  fi
fi

if [ -z "$actual" ]; then
  echo "check-age-key: could not determine the public half of $key_file — skipping."
  exit 0
fi

# --- the comparison --------------------------------------------------------
if [ "$actual" = "$expected" ]; then
  echo "check-age-key: OK — local key matches .sops.yaml ($expected)"
  exit 0
fi

cat <<EOF >&2

check-age-key: MISMATCH — this machine cannot open what the repo is encrypted to.

  .sops.yaml expects:  $expected
  $key_file has:  $actual

This is the 2026-11-03 failure exactly: a plausible-looking key at the right
path that is a recipient of nothing. Your machine is unaffected (it decrypts
its own secrets with its SSH host key); what is broken is YOUR ability to read
or edit secrets here, and the escape hatch for re-keying a reinstalled host.

Fix it by replacing the local key, NOT by editing .sops.yaml — the anchor is
the source of truth and the files on disk are already encrypted to it. Editing
the anchor to match a stray key would require \`sops updatekeys\` on every file
and would re-key the repo to a key that exists on one machine.

Recover the right key from either source, newest-first:

  1. Another machine that already works:
       ssh <other-host> cat ~/.config/sops/age/keys.txt > $key_file
       chmod 600 $key_file
  2. The Proton Pass secure note \`nixcfg/age-key\` (a NOTE, not a login item —
     login items mangle multi-line content). See secrets/README.md.

Then confirm, rather than assuming:

  age-keygen -y $key_file          # must print $expected
  sops -d secrets/common/backup.yaml >/dev/null && echo works

Bypass once if you are mid-rescue:  LEFTHOOK=0 git commit ...

EOF
exit 1
