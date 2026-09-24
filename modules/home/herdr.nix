# herdr, one persistent session per org.
#
# herdr is a terminal multiplexer built around coding agents: a background
# server holds the panes, a client attaches to render them. Closing the client —
# or the terminal window, or losing the session — leaves the panes running, and
# attaching again picks them up where they were. That is the whole reason it is
# here: an agent mid-task survives closing the window.
#
# It already supports named sessions (`herdr --session <name>`), so separating
# the orgs needs no invention: each org gets a session named after it. What this
# module adds is not having to remember that. Running plain `herdr` anywhere
# under an org's directory attaches to that org's session; running it outside
# every org leaves the default session alone.
#
# The mechanism is the same PATH wrapper as modules/home/claude-code-profiles.nix
# — see that module's header for why a wrapper beats a direnv .envrc, which
# applies here unchanged. The difference is that herdr takes a flag rather than
# an environment variable, so the wrapper rewrites ARGUMENTS, and that has to be
# done carefully: `--session` is only meaningful on the bare launch form.
# `herdr session list`, `herdr status`, `herdr server stop` and every other
# subcommand must be passed through untouched, or the wrapper turns working
# commands into usage errors.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  herdrPkg = inputs.herdr.packages.${pkgs.system}.default;

  # Orgs with a directory to match against. Every org qualifies — unlike the
  # workspace rules, this needs no `workspaces`, because attaching to your own
  # session is useful whether or not the org has a screen of its own.
  named = lib.mapAttrsToList (name: org: { inherit name org; }) config.my.orgs;

  # Same quoting rule as the claude wrapper: the literal prefix is quoted and
  # the glob left outside it, so the path matches literally and `*` still globs.
  orgMatch = lib.concatMapStrings (
    { name, org }:
    ''
      case "$here/" in
        ${lib.escapeShellArg org.directory}/*) session=${lib.escapeShellArg name} ;;
      esac
    ''
  ) named;

  wrapper = pkgs.writeShellApplication {
    name = "herdr";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      real=${lib.escapeShellArg "${herdrPkg}/bin/herdr"}

      # Only the bare launch form takes --session. Anything with a subcommand,
      # or that already selects a session or a remote, is passed straight
      # through — rewriting those would break them.
      #
      # The test is "did the caller pass a non-option argument": every
      # subcommand (session, status, server, api, pane, ...) starts with one,
      # and the launch form has none.
      passthrough=no
      for arg in "$@"; do
        case "$arg" in
          --session | --session=* | --remote | --remote=* | --machine | --machine=*)
            passthrough=yes
            ;;
          # Informational flags: answer and exit without touching a session.
          # Harmless either way, but `herdr --version` has no business starting
          # or resolving one.
          --version | -V | --help | -h | --default-config | --skill)
            passthrough=yes
            ;;
          -*) ;;
          *) passthrough=yes ;;
        esac
      done

      if [ "$passthrough" = yes ]; then
        exec "$real" "$@"
      fi

      # Resolved, because the org directories are written as real paths and a
      # symlinked cwd would miss every pattern.
      here=$(pwd -P)
      session=""
      ${orgMatch}

      if [ -n "$session" ]; then
        exec "$real" --session "$session" "$@"
      fi

      exec "$real" "$@"
    '';
  };
in
{
  # Shared with modules/home/org.nix, which launches each org's terminal into
  # that org's session. It uses the WRAPPER rather than the bare binary so both
  # routes into herdr behave identically — one of them silently bypassing the
  # org logic is exactly the bug this option exists to prevent.
  options.my.herdr.package = lib.mkOption {
    internal = true;
    type = lib.types.package;
    description = "The `herdr` on PATH: upstream's binary behind the org-session wrapper.";
  };

  config = {
    my.herdr.package = wrapper;

    # The wrapper is the only `herdr` on PATH; the package itself is not
    # installed alongside it, because two would collide on bin/herdr and which
    # one won would depend on profile ordering.
    home.packages = [ wrapper ];
  };
}
