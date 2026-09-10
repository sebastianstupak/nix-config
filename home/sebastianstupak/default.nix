# home-manager configuration for user "sebastianstupak".
{ ... }:
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
  my.calendars = {
    work.meetings = true; # Outlook/Teams, via Publish a calendar
    personal.meetings = true; # Proton, via Share with anyone
    # holidays = { };
  };

  # Per-user git identity (shared git config lives in modules/home/git.nix).
  programs.git.settings.user = {
    name = "sebastianstupak";
    email = "sebastian.stupak@pm.me";
  };
}
