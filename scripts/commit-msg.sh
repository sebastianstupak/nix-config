#!/usr/bin/env bash
#
# Conventional Commits validator. Blocks the commit (non-zero exit) when the
# header doesn't match:  <type>(<optional-scope>)<optional-!>: <description>
#
# Pure bash + grep — no Nix required — so it runs identically on Windows (Git
# Bash) and NixOS. Invoked by .githooks/commit-msg.
#
# Usage: commit-msg.sh <path-to-commit-message-file>
set -euo pipefail

msg_file="${1:?usage: commit-msg.sh <commit-msg-file>}"

# Header = first line that is neither blank nor a comment.
header="$(grep -vE '^[[:space:]]*(#|$)' "$msg_file" | head -n1 || true)"

# Let git's own generated messages through untouched.
case "$header" in
  "Merge "* | "Revert "* | "fixup! "* | "squash! "* | "amend! "*)
    exit 0
    ;;
esac

types="feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert"
pattern="^(${types})(\([a-z0-9._/-]+\))?!?: .+"

fail() {
  {
    echo "✗ Not a valid Conventional Commit."
    echo
    echo "  format:  <type>(<scope>)!: <description>"
    echo "  types:   ${types//|/, }"
    echo "  scope:   optional — e.g. (home), (workstation), (modules/nixos)"
    echo "  !     :  optional — marks a breaking change"
    echo
    echo "  examples:"
    echo "    feat(home): add zsh with starship prompt"
    echo "    fix(workstation): correct EFI mount point"
    echo "    chore: nix flake update"
    echo "    refactor(modules)!: split desktop into gnome/kde"
    echo
    echo "  your header: ${header:-<empty>}"
    echo
    echo "  bypass once with: git commit --no-verify"
  } >&2
  exit 1
}

[ -n "$header" ] || fail
printf '%s' "$header" | grep -Eq "$pattern" || fail

# Keep subjects readable.
max=72
if [ "${#header}" -gt "$max" ]; then
  echo "✗ Commit subject is ${#header} chars (max ${max}):" >&2
  echo "  ${header}" >&2
  echo "  bypass once with: git commit --no-verify" >&2
  exit 1
fi

exit 0
