# Global git hooks: strip AI attribution from commit messages in EVERY repo,
# not just ones that opted in.
#
# The hard part is composition. git honours exactly one core.hooksPath, and a
# repo-local value silently wins over the global one — that is how husky and
# lefthook installs shadow global hooks (husky#391, lefthook#1248). So a global
# hook cannot simply exist; it has to run its policy and then hand control to
# whatever the repository itself would have run:
#
#   1. this policy
#   2. $GIT_DIR/hooks/<name>          classic per-repo hooks
#   3. lefthook run <name>            if the repo has a lefthook config
#
# Step 2 deliberately resolves $GIT_DIR/hooks literally rather than via
# `git rev-parse --git-path hooks`, because that helper returns core.hooksPath
# when set — which is this directory, and would recurse forever.
#
# Repos that set their own core.hooksPath (this one does, via the dev shell)
# bypass all of the above by design, so their committed hook carries the same
# check independently. See .githooks/commit-msg.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Trailers that are pure attribution: removed silently, since they carry no
  # authored content. Anchored to line starts so a message *discussing* a
  # trailer is not silently mangled.
  stripPattern = "^[[:space:]]*(co-authored-by:[[:space:]]*.*(claude|anthropic)|claude-session:[[:space:]]*|(🤖[[:space:]]*)?generated with[[:space:]]+.*claude)";

  # Anything else mentioning the vendor is a human decision, so it is reported
  # rather than rewritten — silently editing prose would be worse than failing.
  mentionPattern = "claude|anthropic";

  policy = pkgs.writeShellApplication {
    name = "git-strip-ai-attribution";
    runtimeInputs = [
      pkgs.gnugrep
      pkgs.gnused
      pkgs.coreutils
    ];
    # The script is checked by shellcheck via writeShellApplication.
    text = ''
      msg_file="''${1:-}"
      [ -n "$msg_file" ] || exit 0
      [ -r "$msg_file" ] || exit 0

      tmp="$(mktemp)"
      trap 'rm -f "$tmp"' EXIT

      # 1. Drop attribution trailers outright.
      grep -viE ${lib.escapeShellArg stripPattern} "$msg_file" > "$tmp" || true

      # Collapse the blank lines a removed trailer block leaves behind, so the
      # message does not end in a ragged gap.
      sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$tmp" > "$tmp.trimmed" || true
      mv "$tmp.trimmed" "$tmp"

      if ! cmp -s "$msg_file" "$tmp"; then
        cp "$tmp" "$msg_file"
        echo "note: removed AI attribution trailer(s) from the commit message." >&2
      fi

      # 2. Any remaining mention is a human decision — report, do not rewrite.
      #    Comment lines are git's own template and are never committed.
      # printf rather than a heredoc: this text is embedded in a Nix indented
      # string, which strips only the common prefix, so heredoc body lines
      # would keep their relative indentation.
      if grep -v '^[[:space:]]*#' "$msg_file" | grep -qiE ${lib.escapeShellArg mentionPattern}; then
        printf '%s\n' \
          "" \
          "  Commit message mentions Claude / Anthropic." \
          "" \
          "  Attribution trailers are stripped automatically. This is different:" \
          "  the wording appears in the message body, so it is left alone rather" \
          "  than silently rewritten." \
          "" \
          "  Describe the change itself, not the tool used to write it." \
          "" \
          "  To bypass once:  git commit --no-verify" \
          "" >&2
        exit 1
      fi

      exit 0
    '';
  };

  hooksDir = "${config.xdg.configHome}/git/hooks";

  # One dispatcher, symlinked per hook name. $0 tells it which hook it is.
  dispatcher = pkgs.writeShellScript "global-git-hook" ''
    hook_name="$(basename "$0")"

    if [ "$hook_name" = "commit-msg" ]; then
      ${policy}/bin/git-strip-ai-attribution "$@" || exit $?
    fi

    # Delegate to the repository's own hook, if it has one. Resolve $GIT_DIR
    # literally: `git rev-parse --git-path hooks` would return core.hooksPath,
    # i.e. this very directory, and recurse.
    git_dir="$(git rev-parse --absolute-git-dir 2>/dev/null || true)"
    delegate="$git_dir/hooks/$hook_name"
    if [ -n "$git_dir" ] && [ -x "$delegate" ]; then
      # Never re-enter ourselves. If core.hooksPath happens to resolve to the
      # repo's own hooks directory, or this dispatcher has been copied into it,
      # delegating would recurse until the process table gives up.
      self="$(readlink -f "$0" 2>/dev/null || echo "$0")"
      target="$(readlink -f "$delegate" 2>/dev/null || echo "$delegate")"
      if [ "$self" != "$target" ]; then
        exec "$delegate" "$@"
      fi
    fi

    # Otherwise hand off to lefthook when the repo is configured for it.
    if [ -n "$git_dir" ]; then
      top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
      for f in lefthook.yml lefthook.yaml .lefthook.yml .lefthook.yaml; do
        if [ -n "$top" ] && [ -f "$top/$f" ] && command -v lefthook >/dev/null 2>&1; then
          exec lefthook run "$hook_name" "$@"
        fi
      done
    fi

    exit 0
  '';

  # Only the hooks we actually need. Adding every git hook name would mean
  # spawning a shell on operations that currently cost nothing.
  hookNames = [
    "commit-msg"
    "prepare-commit-msg"
  ];
in
{
  xdg.configFile = lib.listToAttrs (
    map (name: {
      name = "git/hooks/${name}";
      value = {
        source = dispatcher;
        executable = true;
      };
    }) hookNames
  );

  programs.git.settings.core.hooksPath = hooksDir;

  # Exposed so the policy can be run by hand, and so the flake check can test
  # the exact script that is installed rather than a copy of it.
  home.packages = [ policy ];
}
