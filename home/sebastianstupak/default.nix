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

  # Per-user git identity (shared git config lives in modules/home/git.nix).
  programs.git.settings.user = {
    name = "sebastianstupak";
    email = "sebastian.stupak@pm.me";
  };
}
