# An org's workspaces, and the `org` command that lands you on them.
#
# The org list itself lives in home/<user>/default.nix; this module is what
# turns an entry with workspaces into a place you can actually go. Using it from
# day to day, and reading the bar: docs/ORGS.md.
#
# An org owns one or more workspaces. The first is its home: `org <name>`
# switches there and — unless its terminal is already sitting there — starts one
# in the org's directory, plus whatever `apps` it declares. The rest are the
# same org's other screens, reachable with the ordinary $mod+N binds. Everything downstream of the directory then agrees without being
# told: git picks the org's commit identity (modules/home/git.nix), `claude`
# picks the org's account and MCP servers (modules/home/claude-code-profiles.nix).
# Starting the terminal somewhere else and cd-ing in works just as well; the
# launcher is a shortcut, not the mechanism.
#
# Workspaces are declared `persistent:true` so they exist from login rather than
# springing into being on first use. That is what lets the bar show a fixed row
# of org glyphs instead of one that reshuffles as you work — and it is why
# waybar's own numeric placeholders are turned down to one (see
# modules/home/waybar.nix); with both, the placeholder wins and every org shows
# up as a bare number.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Only orgs that asked for workspaces. An org without any is still a real
  # org — it has an identity and a directory — it just has nowhere to land.
  named = lib.mapAttrsToList (name: org: { inherit name org; }) (
    lib.filterAttrs (_: org: org.workspaces != [ ]) config.my.orgs
  );

  orgNames = map ({ name, ... }: name) named;

  # The terminal the org's workspace opens with. Taken from the configured
  # package rather than a bare `ghostty`, so this cannot start a different
  # terminal from the one $mod+Return does.
  terminal = "${config.programs.ghostty.package}/bin/ghostty";

  # Wayland app-id of the terminal above, used to recognise a window the
  # launcher itself started. It is compiled into the terminal, so there is
  # nothing in the package to derive it from — but the package does declare it
  # as StartupWMClass, and the `org-terminal-class` flake check asserts the two
  # still agree. If the terminal ever renames its app-id, that check fails
  # rather than the launcher quietly opening a second window every time.
  terminalClass = "com.mitchellh.ghostty";

  # The org's terminal opens straight into that org's herdr session, so the
  # panes and agents from last time are already there. `-e` is ghostty's "run
  # this instead of a shell"; the wrapper would pick the same session from the
  # directory anyway, but naming it here means the window cannot end up on the
  # default session if it somehow starts outside the tree.
  #
  # Closing this window does not end the session: herdr's server keeps the panes
  # running and the next `org <name>` reattaches to them. See
  # modules/home/herdr.nix.
  # `--confirm-close-surface=false` applies to THIS window only, not to the
  # terminal's global setting, so a scratch shell elsewhere still asks before
  # taking a running process down with it.
  #
  # It is off here because the prompt it suppresses says "All terminal sessions
  # in this window will be terminated", and in an org window that is simply
  # untrue: the panes live in herdr's server and closing the window detaches
  # from them. A confirmation that misstates what is about to happen is worse
  # than no confirmation — verified by screenshotting the dialog.
  commandsFor =
    name: org:
    [
      "${terminal} --working-directory=${org.directory} --confirm-close-surface=false -e ${lib.getExe config.my.herdr.package} --session ${name}"
    ]
    ++ org.apps;

  # Hyprland workspace names must be unique, so only the first carries the bare
  # org name and the rest are suffixed. The bar keys its icons off exactly these
  # strings, which is why this is one function rather than two conventions that
  # would drift the first time a third screen is added.
  workspaceName = name: index: if index == 0 then name else "${name}-${toString (index + 1)}";

  # Flattened [{ id, name, org }] over every org workspace, in id order. Shared
  # by the Hyprland rules, the duplicate-id assertion and modules/home/waybar.nix.
  allWorkspaces = lib.sort (a: b: a.id < b.id) (
    lib.concatMap (
      { name, org }:
      lib.imap0 (index: id: {
        inherit id org;
        name = workspaceName name index;
      }) org.workspaces
    ) named
  );

  # One `case` arm per org. Each command is quoted as a single word, so an app
  # with arguments survives the trip into the array intact.
  orgArms = lib.concatMapStrings (
    { name, org }:
    ''
      ${lib.escapeShellArg name})
        screens=(${lib.concatMapStringsSep " " toString org.workspaces})
        dir=${lib.escapeShellArg org.directory}
        apps=(${lib.concatMapStringsSep " " lib.escapeShellArg (commandsFor name org)})
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

      Switch to an org's screen. With no NAME, pick one from a menu.

      SCREEN selects which of the org's workspaces, 1-based, default 1. Screen 1
      is the org's home: it gets a terminal attached to the org's session,
      started if it is not already there. The others are just switched to.

        -l, --list   print the known org names
        -h, --help   show this

      Examples:
        org datadir      the org's home screen, with its terminal
        org datadir 2    the org's second screen
      EOF
      }

      case "''${1:-}" in
        -h | --help) usage; exit 0 ;;
        -l | --list) names; exit 0 ;;
      esac

      target="''${1:-}"
      screen="''${2:-1}"

      case "$screen" in
        "" | *[!0-9]*)
          printf 'org: screen must be a number, got %s\n' "$screen" >&2
          exit 1
          ;;
      esac

      if [ -z "$target" ]; then
        # `|| true`: fuzzel exits non-zero when dismissed with Escape, which is
        # a decision not to switch, not a failure.
        target=$(names | fuzzel --dmenu --prompt 'org ' || true)
        [ -n "$target" ] || exit 0
      fi

      screens=()
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

      if [ "$screen" -lt 1 ] || [ "$screen" -gt "''${#screens[@]}" ]; then
        printf 'org: %s has %d screen(s), asked for %s\n' "$target" "''${#screens[@]}" "$screen" >&2
        exit 1
      fi
      ws="''${screens[$((screen - 1))]}"

      hyprctl dispatch workspace "$ws" > /dev/null

      # Only the org's HOME screen gets a terminal. The others are deliberately
      # left bare: they exist so one org's work can be spread across two
      # screens, and what belongs on the second one is not something this can
      # guess. `org <name> 2` is "take me there", nothing more.
      if [ "$screen" -ne 1 ]; then
        exit 0
      fi

      # Is this org already set up here? The test is "does the workspace have
      # one of our terminals", not "is the workspace empty".
      #
      # Empty was the obvious rule and it is wrong: any window that happens to
      # be sitting on the org's workspace — a browser you opened to look
      # something up — stops `org` from ever opening the org's terminal, and it
      # fails silently, because switching to the workspace is the visible part.
      # Caught by testing it against a workspace that already had a browser on
      # it.
      #
      # Matching on the terminal's own window is the honest test, and it keeps
      # `org <name>` safe to run repeatedly: the second time it is purely "take
      # me there". Matched on initialClass, which a window keeps for life,
      # rather than class, which it does not.
      #
      # Process cwd would be a more precise signal and does not work: ghostty
      # passes the directory to the shell it starts and stays in $HOME itself,
      # so every terminal on the machine looks identical from /proc.
      mine=$(hyprctl clients -j | jq --argjson id "$ws" --arg cls ${lib.escapeShellArg terminalClass} \
        '[.[] | select(.workspace.id == $id and .initialClass == $cls)] | length')
      if [ "$mine" -eq 0 ]; then
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
  # Shared with the `org-terminal-class` flake check rather than repeated there
  # as a literal, so there is one place the app-id is written down.
  options.my.orgLauncher = {
    terminalClass = lib.mkOption {
      internal = true;
      type = lib.types.str;
      description = "Wayland app-id of the terminal the launcher starts.";
    };

    terminalPackage = lib.mkOption {
      internal = true;
      type = lib.types.package;
      description = "The terminal package whose app-id `terminalClass` names.";
    };

    workspaces = lib.mkOption {
      internal = true;
      type = lib.types.listOf (lib.types.attrsOf lib.types.unspecified);
      description = ''
        Every org workspace as { id, name, org }, in id order. The bar needs
        the same names Hyprland gives these workspaces in order to put the
        right glyph on them; sharing the derived list is what stops the naming
        rule from being written down twice.
      '';
    };
  };

  config = lib.mkMerge [
    {
      my.orgLauncher = {
        inherit terminalClass;
        terminalPackage = config.programs.ghostty.package;
        workspaces = allWorkspaces;
      };

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
          # An org with workspaces but no glyph would render as an empty span:
          # a chip you can click but cannot see, which reads as the bar being
          # broken rather than as a missing setting.
          assertion = lib.all ({ org, ... }: org.icon != "") named;
          message = ''
            my.orgs: an org with workspaces has no icon. The bar shows the glyph
            instead of the workspace number, so without one its workspaces are
            invisible. Pick one the bar's font has:
              fc-list ':charset=<codepoint>' family
          '';
        }
        {
          assertion =
            lib.length (lib.unique (map ({ id, ... }: id) allWorkspaces)) == lib.length allWorkspaces;
          message = ''
            my.orgs: two orgs claim the same workspace number. Each needs its
            own, or `org <name>` would take you to someone else's screen and the
            bar would show one org's glyph on another's workspace.
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
          { id, name, ... }: "${toString id}, defaultName:${name}, persistent:true"
        ) allWorkspaces;

        # $mod+O picks an org. The numeric $mod+N binds in hyprland.nix still
        # work and are the faster route once you know which number an org is;
        # this is the one you use when you don't.
        bind = [ "$mod, O, exec, ${lib.getExe orgLauncher}" ];
      };
    })
  ];
}
