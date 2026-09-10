# Calendar. Mirrors any number of published ICS feeds locally — Proton for
# personal, Outlook/M365 for work — and feeds the two things that read them:
#   - GNOME Calendar for the week view, opened by clicking the waybar clock.
#   - khal for the "meetings left today" counter in the bar (the script lives
#     with the other bar scripts, in modules/home/waybar.nix).
#
# This file is the MECHANISM, and it is deliberately provider-agnostic: an ICS
# feed over HTTPS is an ICS feed over HTTPS. The list of calendars is data, and
# lives with the person it belongs to — see `my.calendars` in
# home/sebastianstupak/default.nix.
#
# Neither provider offers anything better than a feed. Proton has no CalDAV and
# no API (its bridge is mail-only); Microsoft 365 dropped CalDAV years ago and
# its replacement, Graph, needs an app registration a work tenant will usually
# not grant. So everything here is READ-ONLY in both directions: events get made
# in Proton's web app or in Outlook/Teams. If you want somewhere writable
# locally, add a local calendar inside GNOME Calendar.
#
#   ICS feed ──vdirsyncer, every 30 min──▶ ~/.local/share/calendars/<name>
#           │                                       └─▶ khal ─▶ waybar
#           └──GNOME Calendar's own web subscription──▶ week view
#
# The two fetch each feed independently, on purpose. GNOME Calendar can only
# subscribe to a URL, and nothing can query the copy inside evolution-data-server
# from a shell script, so the counter needs its own local mirror either way. The
# duplicate GET is a few KB against feeds that regenerate on the provider's own
# lazy schedule; the alternative — running radicale so both read one mirror — is
# a daemon and a pile of moving parts for the same numbers.
#
# PER CALENDAR, two manual steps. The first cannot live in the repo: these URLs
# are capability links, i.e. anyone holding one can read the whole calendar
# (Proton's even carries the decryption key).
#
#   1. Get the feed URL, then drop it where vdirsyncer looks:
#        install -Dm600 /dev/stdin ~/.config/vdirsyncer/<name>-url <<< '<link>'
#      `<name>` is the attribute name used in `my.calendars`. Once secrets/ is
#      wired up, point `urlFile` at the sops path instead.
#
#      Proton:  Calendar ▸ Settings ▸ Share ▸ Share with anyone (paid plans),
#               per calendar. Up to 5 links each. Proton takes up to 8h to
#               reflect an edit in a published link.
#      Outlook: Calendar ▸ Calendar settings ▸ Calendar ▸ Shared calendars ▸
#               Publish a calendar ▸ pick the calendar ▸ "Can view all details"
#               ▸ Publish, then copy the ICS (not HTML) link. If that section is
#               missing entirely, the tenant admin has blocked publishing and
#               there is no ICS to get — that needs IT, not a config change.
#               Microsoft does not document how fast it regenerates a published
#               feed and it is widely reported to lag by hours, so the bar can
#               be honest about OUR last fetch and still show you a stale
#               meeting. Nothing on this machine can fix that.
#
#   2. Paste the same link into GNOME Calendar: Calendars ▸ Add Calendar ▸
#      From Web. If it refuses the URL outright that is gnome-calendar#142 — it
#      sniffs for a .ics extension, which Outlook's ...reachcalendar.ics
#      satisfies but Proton's does not (its link continues past calendar.ics
#      into ?CacheKey=...&PassphraseKey=...).
#
# The week view starts on Monday because of i18n.extraLocaleSettings.LC_TIME in
# modules/nixos/core.nix; GNOME Calendar has no first-day-of-week setting of its
# own. The backend it talks to is enabled in modules/nixos/desktop.nix.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cals = config.my.calendars;
  enabled = cals != { };

  basePath = "${config.xdg.dataHome}/calendars";

  # Kept under basePath rather than in vdirsyncer's usual $XDG_DATA_HOME spot so
  # that one option can hand it to the bar script: vdirsyncer rewrites
  # <pair>.items on every successful sync — even a no-op one — which makes its
  # mtime the honest "last synced" marker per calendar.
  statusPath = "${basePath}/.vdirsyncer-status";

  # Same source of truth the waybar counter reads, so the bar cannot end up
  # looking at a different directory than vdirsyncer writes.
  vdirOf = name: config.accounts.calendar.accounts.${name}.local.path;
in
{
  options.my.calendars = lib.mkOption {
    default = { };
    example = lib.literalExpression ''
      {
        work.meetings = true; # Outlook published feed
        personal.meetings = true; # Proton share link
        holidays = { }; # mirrored and visible, but never counted
      }
    '';
    description = ''
      Published ICS calendar feeds to mirror locally, keyed by the short name
      that khal, vdirsyncer and the local directory all use. Provider-agnostic:
      a Proton share link and an Outlook published-calendar link are both just
      URLs. Each entry needs its own link — see the header of
      modules/home/calendar.nix for where to get one per provider.
    '';
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          options = {
            meetings = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Count this calendar in the waybar "meetings left today" module.
                Off by default, because the useful default for a birthday,
                holiday or subscribed-sports-fixtures feed is to be visible in
                the week view without ever inflating the counter.
              '';
            };

            urlFile = lib.mkOption {
              type = lib.types.str;
              default = "${config.xdg.configHome}/vdirsyncer/${name}-url";
              defaultText = lib.literalExpression ''"''${config.xdg.configHome}/vdirsyncer/‹name›-url"'';
              description = ''
                Path to a file containing nothing but this calendar's feed URL.
                Read at sync time via vdirsyncer's `url.fetch`, so the link
                never enters the Nix store or git.
              '';
            };
          };
        }
      )
    );
  };

  # Read by the waybar counter for its staleness check. An option rather than
  # the same string typed out in two modules, so the bar and the syncer cannot
  # disagree about where the marker lives.
  options.my.calendarStatusPath = lib.mkOption {
    type = lib.types.str;
    internal = true;
    default = statusPath;
    description = "Directory holding vdirsyncer's per-pair sync status files.";
  };

  config = lib.mkIf enabled {
    home.packages = [ pkgs.gnome-calendar ];

    accounts.calendar = {
      inherit basePath;

      # local.{type,path,fileExt} default to filesystem / basePath/<name> /
      # ".ics", which is exactly the vdir khal wants.
      #
      # `remote` is deliberately left null even though there IS one: the
      # framework can only express a feed URL as a plain string, and that string
      # would land in git and in the world-readable store. The hand-written
      # vdirsyncer config below is the whole reason why.
      #
      # No `primary` either — it only feeds khal's default_calendar, which
      # matters for `khal new`, and every calendar here is read-only.
      accounts = lib.mapAttrs (_: _: {
        khal = {
          enable = true;
          type = "calendar";
        };
      }) cals;
    };

    programs.khal = {
      enable = true;

      # These formats are load-bearing, not cosmetic. The waybar counter asks
      # khal for each event's `end` and compares it against `date` output as a
      # STRING to decide what is still ahead, so the format has to be
      # zero-padded and big-endian to sort correctly. Anything locale-shaped
      # would break that the moment LC_TIME changes — and it just did (core.nix).
      #
      # Timezones are left unset: khal falls back to the system zone, which
      # time.timeZone already pins. Naming Europe/Bratislava here too would just
      # be a second copy to keep in step.
      locale = {
        dateformat = "%Y-%m-%d";
        longdateformat = "%Y-%m-%d";
        timeformat = "%H:%M";
        datetimeformat = "%Y-%m-%d %H:%M";
        longdatetimeformat = "%Y-%m-%d %H:%M";
      };
    };

    # Hand-written instead of generated from accounts.calendar, for the one
    # reason given above: `url.fetch` keeps each share link out of the store, and
    # the HM framework has no option that emits it. The mechanism is undocumented
    # but real — vdirsyncer's Config.get_storage_args runs expand_fetch_params
    # over every storage section, and that strips a `.fetch` suffix off ANY key,
    # not just password (strategies: command, shell, prompt).
    #
    # One pair per calendar. vdirsyncer syncs pairs independently and keeps
    # per-pair status, so a calendar whose link has gone stale (or whose urlFile
    # is missing) fails on its own and leaves the others alone — the service goes
    # red, and the bar's staleness indicator follows the OLDEST counted calendar.
    xdg.configFile."vdirsyncer/config".text = ''
      [general]
      status_path = "${statusPath}"
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (name: cal: ''

        [pair ${name}]
        a = "${name}_local"
        b = "${name}_remote"
        # A shared ICS link is a single calendar, not a discoverable set of
        # collections, so there is nothing to enumerate.
        collections = null

        [storage ${name}_local]
        type = "filesystem"
        path = "${vdirOf name}"
        fileext = ".ics"

        [storage ${name}_remote]
        type = "http"
        url.fetch = ["command", "cat", "${cal.urlFile}"]
      '') cals
    );

    services.vdirsyncer = {
      enable = true;
      # Proton takes up to 8h to reflect an edit in a shared link, so anything
      # tighter than this is noise aimed at their servers. The timer only runs
      # while logged in, which is fine for a laptop.
      frequency = "*:0/30";
    };

    # Two gaps in the HM module, both of which leave the timer failing forever on
    # a fresh machine (its source carries a `# TODO vdirsyncer discover`):
    #   - `sync` refuses to run before `discover`, even with collections = null:
    #     "Please run `vdirsyncer discover proton` before synchronization."
    #   - `discover` then asks "Should vdirsyncer attempt to create it? [y/N]"
    #     when a local collection directory is missing — and a systemd unit
    #     answers prompts with EOF, i.e. N, i.e. nothing ever gets created.
    # Creating the directories first turns discover into a silent no-op, so it is
    # safe to re-run ahead of every sync. Bare `discover` covers every pair.
    systemd.user.services.vdirsyncer.Service.ExecStartPre = [
      "${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArgs (map vdirOf (lib.attrNames cals))}"
      "${config.services.vdirsyncer.package}/bin/vdirsyncer discover"
    ];
  };
}
