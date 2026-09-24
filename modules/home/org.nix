# One workspace per org, and the `org` command that lands you on it.
#
# The org list itself lives in home/<user>/default.nix; this module is what
# turns an entry with a `workspace` into a place you can actually go.
#
# `org <name>` switches to that org's workspace and — only if nothing is open
# there — starts a terminal in the org's directory plus whatever `apps` it
# declares. Everything downstream of the directory then agrees without being
# told: git picks the org's commit identity (modules/home/git.nix), `claude`
# picks the org's account and MCP servers (modules/home/claude-code-profiles.nix).
# Starting the terminal somewhere else and cd-ing in works just as well; the
# launcher is a shortcut, not the mechanism.
#
# Workspaces are declared `persistent:true` so they exist from login rather than
# springing into being on first use. That is what lets the bar show four org
# names in a fixed layout instead of a row that reshuffles as you work — and it
# is why waybar's own numeric placeholders are turned down to one (see
# modules/home/waybar.nix); with both, the placeholder wins and every org shows
# up as a bare number.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Only orgs that asked for a workspace. An org without one is still a real
  # org — it has an identity and a directory — it just has nowhere to land.
  named = lib.mapAttrsToList (name: org: { inherit name org; }) (
    lib.filterAttrs (_: org: org.workspace != null) config.my.orgs
  );

  orgNames = map ({ name, ... }: name) named;

  # The terminal the org's workspace opens with. Taken from the configured
  # package rather than a bare `ghostty`, so this cannot start a different
  # terminal from the one $mod+Return does.
  terminal = "${config.programs.ghostty.package}/bin/ghostty";

  commandsFor = org: [ "${terminal} --working-directory=${org.directory}" ] ++ org.apps;

  # One `case` arm per org. Each command is quoted as a single word, so an app
  # with arguments survives the trip into the array intact.
  orgArms = lib.concatMapStrings (
    { name, org }:
    ''
      ${lib.escapeShellArg name})
        ws=${toString org.workspace}
        dir=${lib.escapeShellArg org.directory}
        apps=(${lib.concatMapStringsSep " " lib.escapeShellArg (commandsFor org)})
        ;;
    ''
  ) named;

  orgLauncher = pkgs.writeShellApplication {
    name = "org";
    runtimeInputs = [
      config.wayland.windowManager.hyprland.package # hyprctl
      pkgs.coreutils
      pkgs.fuzzel
      pkgs.jq
    ];
    text = ''
      names() { printf '%s\n' ${lib.concatMapStringsSep " " lib.escapeShellArg orgNames}; }

      usage() {
        cat <<'EOF'
      Usage: org [NAME]

      Switch to an org's workspace, starting its apps if nothing is open there
      yet. With no NAME, pick one from a menu.

        -l, --list   print the known org names
        -h, --help   show this
      EOF
      }

      case "''${1:-}" in
        -h | --help) usage; exit 0 ;;
        -l | --list) names; exit 0 ;;
      esac

      target="''${1:-}"
      if [ -z "$target" ]; then
        # `|| true`: fuzzel exits non-zero when dismissed with Escape, which is
        # a decision not to switch, not a failure.
        target=$(names | fuzzel --dmenu --prompt 'org ' || true)
        [ -n "$target" ] || exit 0
      fi

      ws=""
      dir=""
      apps=()

      case "$target" in
        ${orgArms}
        *)
          printf 'org: no org named %s\n\nknown orgs:\n' "$target" >&2
          names >&2
          exit 1
          ;;
      esac

      hyprctl dispatch workspace "$ws" > /dev/null

      # Start the apps only on an empty workspace, so `org datadir` is safe to
      # run repeatedly — the second time it is purely "take me there".
      # `add // 0` because a workspace that has never been used is absent from
      # the list entirely rather than present with zero windows.
      open=$(hyprctl workspaces -j | jq --argjson id "$ws" '[.[] | select(.id == $id) | .windows] | add // 0')
      if [ "$open" -eq 0 ]; then
        # The directory is created at activation, but a deleted one would make
        # the terminal start somewhere unexpected — and the whole point of the
        # workspace is which directory it starts in.
        [ -d "$dir" ] || mkdir -p "$dir"

        for cmd in "''${apps[@]}"; do
          # `[workspace N silent]` pins the window even though we just switched:
          # a slow-starting app would otherwise land wherever focus had moved to
          # by the time it mapped. `silent` suppresses the focus change that the
          # rule would otherwise cause for each one.
          hyprctl dispatch exec "[workspace $ws silent] $cmd" > /dev/null
        done
      fi
    '';
  };
in
{
  config = lib.mkMerge [
    {
      # Every org's directory, workspace or not. git's `includeIf gitdir:` and
      # the Claude Code profile both key on these paths, and a path that does
      # not exist yet is a rule that silently does nothing.
      home.activation.orgDirectories = lib.hm.dag.entryAfter [ "writeBoundary" ] (
        lib.concatMapStrings (org: ''
          mkdir -p ${lib.escapeShellArg org.directory}
        '') (lib.attrValues config.my.orgs)
      );
    }

    (lib.mkIf (named != [ ]) {
      assertions = [
        {
          assertion = lib.length (lib.unique (map ({ org, ... }: org.workspace) named)) == lib.length named;
          message = ''
            my.orgs: two orgs claim the same workspace. Each org needs its own,
            or `org <name>` would take you to someone else's screen.
          '';
        }
      ];

      home.packages = [ orgLauncher ];

      wayland.windowManager.hyprland.settings = {
        # `defaultName` labels the workspace; `persistent:true` makes it exist
        # before it is first used, which is what keeps the bar's layout fixed.
        # Note defaultName only applies at CREATION — a workspace that already
        # exists under its number keeps that number until the next Hyprland
        # start, which is why this reads as a no-op on a live `hyprctl reload`.
        workspace = map (
          { name, org }: "${toString org.workspace}, defaultName:${name}, persistent:true"
        ) named;

        # $mod+O picks an org. The numeric $mod+N binds in hyprland.nix still
        # work and are the faster route once you know which number an org is;
        # this is the one you use when you don't.
        bind = [ "$mod, O, exec, ${lib.getExe orgLauncher}" ];
      };
    })
  ];
}
