# Per-directory Claude Code profiles.
#
# A profile is a tree of repos that must run under a DIFFERENT Claude account
# from the rest of this machine: its own login and subscription, its own MCP
# servers, its own history and project state, its own CLAUDE.md. Claude Code
# keeps all of that under one directory, chosen by $CLAUDE_CONFIG_DIR, so a
# profile is really just "which config dir does `claude` use here".
#
# The enforcement is a WRAPPER on PATH named `claude`, not a direnv .envrc.
# Both can export the variable; only the wrapper cannot be bypassed by accident:
#
#   * direnv only loads the .envrc it finds in the directory you are standing
#     in. A repo at ~/dev/hettify/foo with its own .envrc (`use flake`,
#     which every Nix project here has) does NOT inherit the parent one unless
#     it remembers to call `source_up` — so the very repos the profile exists
#     for are exactly the ones that would silently fall back to the personal
#     login.
#   * .envrc also needs `direnv allow` re-run every time the file changes, and
#     a not-yet-allowed .envrc fails open: you get the default account with a
#     warning that is easy to scroll past.
#
# The wrapper decides from $PWD instead, so it is right in a subdirectory, in a
# script, in an editor terminal, and on the first run after a rebuild. Because
# it is the only `claude` installed (dev.nix deliberately does not install
# pkgs.claude-code), there is no second binary to reach around it.
#
# It also refuses to start on an account mismatch — see `account` below. That is
# the part that makes "separate subscription" a guarantee rather than a habit:
# logging into the work tree with the personal account stops being a thing you
# can do without noticing.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.claude;
  homeDir = config.home.homeDirectory;

  # [ { name = "hettify"; value = <profile>; } ... ], the form every generator
  # below wants — each needs the attribute name as well as the value.
  named = lib.mapAttrsToList (name: profile: { inherit name profile; }) cfg.profiles;

  # Quoting note for every `case` pattern here: the literal prefix is quoted and
  # the glob is left outside it ("/path"/*), so a path is matched literally
  # while `*` still globs. Quoting the whole pattern would disable the glob;
  # quoting none of it would let a path metacharacter match something else.
  profileMatch = lib.concatMapStrings (
    { name, profile }:
    ''
      case "$here/" in
        ${lib.escapeShellArg profile.directory}/*)
          profile_name=${lib.escapeShellArg name}
          config_dir=${lib.escapeShellArg profile.configDir}
          want_account=${lib.escapeShellArg (if profile.account == null then "" else profile.account)}
          ;;
      esac
    ''
  ) named;

  # Standing outside every profile tree, a profile's config dir inherited from
  # the environment is dropped rather than used. Without this, one `cd` out of
  # the work tree in a shell that still has the variable exported would put a
  # personal repo on the work subscription — the mistake this module exists to
  # prevent, in the other direction.
  profileConfigDirs = map ({ profile, ... }: profile.configDir) named;
  dropInheritedConfigDir = lib.optionalString (profileConfigDirs != [ ]) ''
    case "''${CLAUDE_CONFIG_DIR:-}" in
      ${lib.concatMapStringsSep " | " lib.escapeShellArg profileConfigDirs})
        unset CLAUDE_CONFIG_DIR
        ;;
    esac
  '';

  claudeWrapper = pkgs.writeShellApplication {
    name = "claude";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      # Resolved, because the profile directories are written as real paths and
      # a symlinked cwd would otherwise miss every pattern.
      here=$(pwd -P)

      profile_name=""
      config_dir=""
      want_account=""

      ${profileMatch}
      if [ -n "$config_dir" ]; then
        mkdir -p "$config_dir"
        export CLAUDE_CONFIG_DIR="$config_dir"

        # Claude Code records the signed-in account in <config dir>/.claude.json.
        # An empty value means "never logged in here yet", which has to be
        # allowed or there would be no way to perform the first login.
        if [ -n "$want_account" ]; then
          have=""
          if [ -r "$config_dir/.claude.json" ]; then
            have=$(jq -r '.oauthAccount.emailAddress // empty' "$config_dir/.claude.json" 2>/dev/null || true)
          fi
          if [ -n "$have" ] && [ "$have" != "$want_account" ]; then
            cat >&2 <<EOF
      claude: refusing to start — wrong account for the '$profile_name' profile.

        expected:  $want_account
        signed in: $have
        config:    $config_dir

      Everything under this directory is meant to run on that account's
      subscription. Sign the profile in again:

        cd $here && claude
        /login

      or, if the expected address is the stale one, correct
      my.claude.profiles.$profile_name.account in nix-config.
      EOF
            exit 1
          fi
        fi
      else
      ${dropInheritedConfigDir}
      fi

      exec ${pkgs.claude-code}/bin/claude "$@"
    '';
  };

  profileType = lib.types.submodule (
    { name, ... }:
    {
      options = {
        directory = lib.mkOption {
          type = lib.types.str;
          # Inherited from the org of the same name, so the two cannot drift.
          # They already drifted once — a profile pointing at ~/dev/nettify
          # while the org was ~/dev/hettify gives you a tree with the work
          # Claude account and the wrong commit identity, and another with the
          # right identity and the personal account. Both look fine until
          # something is pushed. Naming the profile after the org is now enough
          # to keep them on one path; the fallback repeats my.orgs' own default
          # for a profile that is not an org.
          default = config.my.orgs.${name}.directory or "${homeDir}/dev/${name}";
          defaultText = lib.literalExpression ''config.my.orgs.‹name›.directory, or "''${config.home.homeDirectory}/dev/‹name›"'';
          example = "/home/alice/dev/acme";
          description = ''
            Absolute path of the tree this profile owns. `claude` started in
            this directory or anywhere below it uses this profile.

            Defaults to the directory of the org with the same name, so an org
            listed in `my.orgs` needs only `my.claude.profiles.<org> = { ... }`
            to get a profile rooted in the right place.
          '';
        };

        configDir = lib.mkOption {
          type = lib.types.str;
          default = "${homeDir}/.config/claude-code/${name}";
          defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/.config/claude-code/<name>"'';
          description = ''
            Value of $CLAUDE_CONFIG_DIR for this profile: where its credentials,
            MCP servers, history and project state live. Deliberately NOT inside
            `directory` — that tree holds git repos, and an OAuth refresh token
            one `git add -A` away from a work remote is not a risk worth taking
            for tidiness.
          '';
        };

        account = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "alice@acme.com";
          description = ''
            Email address this profile must be signed in as. `claude` refuses to
            start in `directory` when the profile is signed into anything else,
            which is what keeps the tree on the intended subscription.

            Leave null until the first login — there is nothing to compare
            against yet — then set it to the address `/status` reports.
          '';
        };

        mcpServers = lib.mkOption {
          type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
          default = { };
          example = lib.literalExpression ''
            { linear = { type = "http"; url = "https://mcp.linear.app/mcp"; }; }
          '';
          description = ''
            MCP servers available to this profile and no other. They are merged
            into the profile's own .claude.json, so they are reachable from
            every repo under `directory` and invisible everywhere else on this
            machine — which is the scoping a per-project .mcp.json cannot give
            you across a whole tree of repos.

            Merged, not replaced: a server removed from here stays configured
            until `claude mcp remove <name>` is run inside the profile. That is
            on purpose — this activation must never delete a server added by
            hand.

            Remote servers still need an interactive OAuth handshake: run `/mcp`
            in the profile once to authorise.
          '';
        };

        instructions = lib.mkOption {
          type = lib.types.nullOr lib.types.lines;
          default = null;
          description = ''
            Seed contents for `''${directory}/CLAUDE.md`, written only when that
            file does not exist yet. Copied rather than symlinked into the store
            so it stays writable: this is a file both you and Claude Code (the
            `#` memory shortcut) append to as the conventions of the tree become
            clear, and a read-only symlink would break that.
          '';
        };
      };
    }
  );
in
{
  options.my.claude = {
    profiles = lib.mkOption {
      type = lib.types.attrsOf profileType;
      default = { };
      description = ''
        Claude Code profiles keyed by short name. See the header of
        modules/home/claude-code-profiles.nix for what a profile is and why the
        switching is done by a PATH wrapper.
      '';
    };

    configDirs = lib.mkOption {
      internal = true;
      type = lib.types.listOf lib.types.str;
      description = ''
        Every Claude Code config dir on this machine: the default one plus one
        per profile. Shared with modules/home/claude-code.nix, which applies the
        notification channel and bell hook to each of them — a profile that had
        to be configured separately would quietly lose them.
      '';
    };
  };

  config = {
    my.claude.configDirs = [ "${homeDir}/.claude" ] ++ profileConfigDirs;

    # The only `claude` on PATH. dev.nix installs no claude-code package of its
    # own; two would collide on bin/claude anyway, and the loser would depend on
    # profile ordering.
    home.packages = [ claudeWrapper ];

    home.activation.claudeCodeProfiles = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      lib.concatMapStrings (
        { name, profile }:
        let
          seed =
            lib.optionalString (profile.instructions != null)
              # Written via a store file rather than a heredoc so the text cannot
              # be mangled by shell expansion on its way through activation.
              ''
                if [ ! -e ${lib.escapeShellArg "${profile.directory}/CLAUDE.md"} ]; then
                  install -m 644 ${pkgs.writeText "claude-md-${name}" profile.instructions} ${lib.escapeShellArg "${profile.directory}/CLAUDE.md"}
                  echo "claude-code: seeded ${profile.directory}/CLAUDE.md"
                fi
              '';

          mcp = lib.optionalString (profile.mcpServers != { }) ''
            tmp="$(mktemp)"
            if ${pkgs.jq}/bin/jq \
                 --argjson servers ${lib.escapeShellArg (builtins.toJSON profile.mcpServers)} \
                 '.mcpServers = ((.mcpServers // {}) + $servers)' \
                 "$state" > "$tmp" 2>/dev/null; then
              # Replace only on a clean parse+write. .claude.json also holds the
              # credentials pointer and every per-project setting for this
              # profile; a truncated one is a re-login and a lost history.
              if ! ${pkgs.diffutils}/bin/cmp -s "$state" "$tmp"; then
                mv "$tmp" "$state"
                echo "claude-code: ${name} mcp servers applied (${lib.concatStringsSep ", " (lib.attrNames profile.mcpServers)})"
              else
                rm -f "$tmp"
              fi
            else
              rm -f "$tmp"
              echo "claude-code: $state is not valid JSON; mcp servers left unset" >&2
            fi
          '';
        in
        ''
          mkdir -p ${lib.escapeShellArg profile.directory} ${lib.escapeShellArg profile.configDir}

          # Credentials live here. 0700 before anything is written into it, not
          # after — Claude Code creates .credentials.json 0600 itself, but the
          # directory listing should not be world-readable either.
          chmod 700 ${lib.escapeShellArg profile.configDir}

          state=${lib.escapeShellArg "${profile.configDir}/.claude.json"}
          [ -s "$state" ] || echo '{}' > "$state"

          ${mcp}
          ${seed}
        ''
      ) named
    );
  };
}
