# home-manager configuration for user "sebastianstupak".
#
# `osConfig` is the NixOS-level config of the host this profile is attached to.
# home-manager passes it whenever it runs as a NixOS module, which is how this
# file reads the sops secret paths declared in hosts/workstation/default.nix
# instead of repeating "/run/secrets/..." literals that nothing would check.
{ osConfig, ... }:
{
  imports = [ ../../modules/home ];

  home = {
    username = "sebastianstupak";
    homeDirectory = "/home/sebastianstupak";

    # The home-manager release this profile was created with. Keep in sync with
    # the host's system.stateVersion; do not bump it casually.
    stateVersion = "26.05";
  };

  # Calendar feeds to mirror locally, keyed by the short name that khal,
  # vdirsyncer and the directory under ~/.local/share/calendars all share. The
  # names are only meaningful on this machine — rename or add freely, but each
  # entry needs its own feed URL at ~/.config/vdirsyncer/<name>-url. Where to get
  # one per provider, and the rest of the setup: modules/home/calendar.nix.
  #
  # `meetings` is what the waybar counter counts. Leave it off for anything that
  # would inflate the number without being something you attend — birthdays,
  # public holidays, a subscribed fixtures feed.
  # The URLs come from sops rather than the default hand-installed
  # ~/.config/vdirsyncer/<name>-url. That default needs a manual step per machine
  # that no rebuild can reproduce, so a reinstall silently loses both feeds and
  # the bar's meeting counter goes quiet. Encrypted in git, they survive it.
  # A new calendar needs a matching secret in hosts/workstation/default.nix.
  # One group per bar counter, each holding as many feeds as it needs. Feed names
  # are prefixed with where they come from, because that is the thing you need to
  # know when one of them stops updating — and the name is what shows up in
  # `systemctl --user status vdirsyncer`, in ~/.local/share/calendars/, and in
  # the hover when a group has more than one feed.
  #
  # Adding a feed: a key in secrets/calendars.yaml, a matching `sops.secrets`
  # entry in hosts/workstation/default.nix, and a line here. Distinct icons are
  # the point of splitting the counts — two 󰃭 chips would be a puzzle — and both
  # of these are covered by JetBrainsMono NF (`fc-list ':charset=f00d6'`).
  my.calendars = {
    work = {
      icon = "󰃖"; # briefcase
      order = 10;
      feeds = {
        # Outlook/Teams, via Calendar settings ▸ Shared calendars ▸ Publish.
        outlook = {
          # Names the calendar in GNOME Calendar's sidebar, and tags events in
          # the bar tooltip once a group holds more than one feed.
          label = "Work (Outlook)";
          urlFile = osConfig.sops.secrets.calendar-work-url.path;
        };
        # outlook-team = {
        #   label = "Team";
        #   urlFile = osConfig.sops.secrets.calendar-work-team-url.path;
        # };
        # outlook-oncall = {
        #   meetings = false; # mirrored, but not something you attend
        #   urlFile = osConfig.sops.secrets.calendar-work-oncall-url.path;
        # };
      };
    };

    personal = {
      icon = "󰋜"; # house
      order = 20;
      feeds = {
        # Proton, via Calendar ▸ Settings ▸ Share ▸ Share with anyone.
        proton = {
          label = "Personal (Proton)";
          urlFile = osConfig.sops.secrets.calendar-personal-url.path;
        };
        # proton-family = {
        #   label = "Family";
        #   urlFile = osConfig.sops.secrets.calendar-family-url.path;
        # };
      };
    };

    # A group with meetings = false is mirrored for the week view and never gets
    # a counter — birthdays, public holidays, a fixtures feed.
    # holidays = {
    #   meetings = false;
    #   feeds.proton-holidays.urlFile = osConfig.sops.secrets.calendar-holidays-url.path;
    # };
  };

  # hettify runs on a different Claude account and subscription from everything
  # else on this machine. Declaring it here rather than in the module keeps the
  # module about the mechanism and this file about who I am — same split as
  # my.calendars above.
  #
  # No `directory`: the profile is named after the org, so it inherits
  # my.orgs.hettify.directory. That is what stops the Claude account and the
  # commit identity from ending up on two different paths.
  #
  # How the switch is enforced, and why it is a PATH wrapper rather than a
  # direnv .envrc: modules/home/claude-code-profiles.nix.
  my.claude.profiles.hettify = {
    # Set this to the address `/status` reports after the first login in that
    # tree. Until it is set, any account is accepted there — there is nothing to
    # compare against before a login has happened. Once set, `claude` refuses to
    # start under ~/dev/hettify signed in as anyone else, which is what stops
    # that work from quietly landing on the personal subscription (or the
    # reverse).
    # account = "sebastian.stupak@hettify.example";

    # Work-only MCP servers. They live in this profile's own .claude.json, so
    # Linear is reachable from every repo under ~/dev/hettify and from nowhere
    # else — no personal session can see the work tracker. Authorise once with
    # `/mcp` inside the profile; the handshake is interactive OAuth.
    mcpServers.linear = {
      type = "http";
      url = "https://mcp.linear.app/mcp";
    };

    # Seeds ~/dev/hettify/CLAUDE.md on the next activation, and only if that
    # file does not exist yet — it stays a normal writable file afterwards, so
    # both hand edits and Claude Code's `#` memory shortcut keep working. It
    # sits at the top of the tree, so every repo below inherits it.
    instructions = ''
      # Hettify

      Everything under `~/dev/hettify` runs on the hettify Claude account: its own
      login and subscription, its own MCP servers, its own history. That is
      enforced by the `claude` wrapper on PATH, not by convention — see
      `my.claude.profiles.hettify` in the personal nix-config.

      ## Boundaries

      - Hettify code, tickets and credentials stay inside this tree.
      - Do not read from or copy into repositories outside it.
      - Linear is the tracker for this org and is available here via MCP. Prefer
        it over guessing at ticket state.

      ## Conventions

      Fill these in as they become clear — build/test commands, review rules,
      deploy steps, whatever turns out to be the thing you explain twice.
    '';
  };

  # The orgs this machine is used for. Directory is the boundary: anything under
  # ~/dev/<org>/ commits as that org (see modules/home/orgs.nix).
  #
  # One address for all of them, deliberately. Each org still pins it explicitly
  # instead of inheriting the global identity below, so that changing the global
  # address later does not silently re-author four orgs' worth of commits — the
  # answer to "who does this org commit as" stays written down per org.
  #
  # If an org ever needs its own address (a GitHub org that enforces a verified
  # company domain, a CLA that checks the author), change that one line; nothing
  # else moves.
  my.orgs =
    let
      me = "sebastian.stupak@pm.me";
    in
    {
      personal.email = me;
      datadir.email = me;
      hettify.email = me;
      bunny.email = me;
    };

  # Per-user git identity (shared git config lives in modules/home/git.nix).
  programs.git.settings.user = {
    name = "sebastianstupak";
    email = "sebastian.stupak@pm.me";
  };
}
