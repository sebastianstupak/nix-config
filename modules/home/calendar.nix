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
  groups = config.my.calendars;

  # One entry per feed, with its group's identity folded in and `meetings`
  # resolved (feed overrides group). Exposed as my.calendarFeeds so the bar
  # module reads the same resolution rather than reimplementing it.
  feeds = lib.concatMapAttrs (
    groupName: group:
    lib.mapAttrs (_: feed: {
      group = groupName;
      inherit (group) icon order;
      inherit (feed) label urlFile;
      meetings = if feed.meetings == null then group.meetings else feed.meetings;
    }) group.feeds
  ) groups;

  enabled = feeds != { };

  # ONE mirror, two readers. vdirsyncer writes each feed straight into the
  # directory layout radicale serves from, so:
  #
  #   feed ──vdirsyncer──▶ <collections>/<feed>/*.ics ──▶ khal ──▶ waybar counters
  #                                     └──▶ radicale (localhost) ──▶ GNOME Calendar
  #
  # The alternative — letting GNOME Calendar subscribe to the upstream URLs
  # itself — fetched everything twice and let the week view and the bar disagree
  # about what "today" holds, which is exactly the kind of drift you cannot debug
  # by looking at either one. This way there is a single fetch and a single copy.
  #
  # radicale's layout is <filesystem_folder>/collection-root/<user>/<collection>
  # (see _get_collection_root_folder in its multifilesystem storage), and a
  # collection is any directory holding a .Radicale.props that tags it
  # VCALENDAR. That is byte-compatible with what vdirsyncer's filesystem storage
  # produces — one .ics per item — so nothing has to translate between them.
  radicaleRoot = "${config.xdg.dataHome}/radicale";
  basePath = "${radicaleRoot}/collection-root/${config.home.username}";

  # Deliberately NOT under basePath any more: everything in there is served by
  # radicale, and vdirsyncer's status files are not calendars.
  statusPath = "${config.xdg.dataHome}/vdirsyncer-status";

  # localhost only, and note there is no authentication: radicale is reachable
  # from this machine alone, by the one account that already owns the files it
  # serves. Adding htpasswd would mean generating and storing a password for the
  # user to hand back to themselves.
  radicalePort = 5232;

  radicaleConfig = pkgs.writeText "radicale.conf" ''
    [server]
    hosts = localhost:${toString radicalePort}

    [auth]
    type = none

    [storage]
    filesystem_folder = ${radicaleRoot}

    [logging]
    level = warning
  '';

  # Marks each vdir as a calendar collection for radicale, and names it. Written
  # at activation rather than by hand: radicale creates these itself only for
  # collections made THROUGH it, and these are made by vdirsyncer behind its
  # back. Idempotent, and it leaves any other key radicale adds later alone by
  # only writing when the file is missing or lacks the VCALENDAR tag.
  collectionProps = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: feed: ''
      dir=${lib.escapeShellArg "${basePath}/${name}"}
      props="$dir/.Radicale.props"
      mkdir -p "$dir"
      if ! ${pkgs.gnugrep}/bin/grep -qs VCALENDAR "$props"; then
        printf '%s' ${
          lib.escapeShellArg (
            builtins.toJSON {
              tag = "VCALENDAR";
              "D:displayname" = feed.label;
            }
          )
        } > "$props"
        echo "calendar: tagged $dir as a radicale collection"
      fi
    '') feeds
  );

  # GNOME Calendar reads calendars registered with evolution-data-server, and
  # nothing else — a vdir is invisible to it. So subscribe it to radicale.
  #
  # The key-file format is undocumented; this shape is the one that was verified
  # working end to end (EDS accepted the source, the webcal backend fetched, and
  # the events landed in ~/.cache/evolution/calendar/<uid>/cache.db):
  #   * `Parent=` empty. The only stub this EDS build has is local-stub, so a
  #     web calendar sits at the top level.
  #   * The URI is assembled from [Security] Method + [Authentication] Host/Port
  #     + [WebDAV Backend] ResourcePath, not stored as one string.
  #   * `User=` empty with Method=none. Naming a user makes EDS want credentials
  #     and the calendar then sits there unauthenticated.
  edsSources = lib.mapAttrsToList (name: feed: {
    inherit name;
    text = ''
      [Data Source]
      DisplayName=${feed.label}
      Enabled=true
      Parent=

      [Calendar]
      BackendName=webcal
      Enabled=true
      Selected=true

      [Authentication]
      Host=localhost
      Method=none
      Port=${toString radicalePort}
      RememberPassword=false
      User=

      [Security]
      Method=none

      [WebDAV Backend]
      AvoidIfmatch=false
      CalendarAutoSchedule=false
      ResourcePath=/${config.home.username}/${name}/
      ResourceQuery=

      [Offline]
      StaySynchronized=true

      [Refresh]
      Enabled=true
      IntervalMinutes=30
    '';
  }) feeds;

  # Same source of truth the waybar counter reads, so the bar cannot end up
  # looking at a different directory than vdirsyncer writes.
  vdirOf = name: config.accounts.calendar.accounts.${name}.local.path;
in
{
  options.my.calendars = lib.mkOption {
    default = { };
    example = lib.literalExpression ''
      {
        work = {
          icon = "󰃖";
          order = 10;
          feeds = {
            outlook.urlFile = "/run/secrets/calendar-work-url";
            outlook-team = {
              label = "Team";
              urlFile = "/run/secrets/calendar-work-team-url";
            };
            outlook-oncall = {
              meetings = false; # mirrored, but not a thing you attend
              urlFile = "/run/secrets/calendar-work-oncall-url";
            };
          };
        };
        holidays = {
          meetings = false; # visible in the week view, never counted
          feeds.proton-holidays.urlFile = "/run/secrets/calendar-holidays-url";
        };
      }
    '';
    description = ''
      Published ICS calendar feeds to mirror locally, grouped by what they are
      *for*. One group is one bar counter with one icon: all the work feeds sum
      into a work number, all the personal ones into a personal number.

      Provider-agnostic — a Proton share link and an Outlook published-calendar
      link are both just URLs — so prefix the feed names with their origin
      (`outlook-team`, `proton-family`) rather than encoding it in the schema.
      Feed names are the vdir directory and the khal calendar name, so they must
      be unique across groups; an assertion enforces that.
    '';
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          icon = lib.mkOption {
            type = lib.types.str;
            default = "󰃭";
            description = ''
              Glyph for this group's bar counter. Nerd Font (JetBrainsMono NF is
              the bar font — check coverage with `fc-list ':charset=f00d6'`
              before picking something exotic, or it renders as tofu). Give each
              group a distinct one: telling two counters apart is the entire
              point of splitting them.
            '';
          };

          order = lib.mkOption {
            type = lib.types.int;
            default = 50;
            description = ''
              Bar position among the counters, ascending. Ties break
              alphabetically. Exists because attribute sets are unordered, so
              without it "personal" would always sit left of "work".
            '';
          };

          meetings = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Whether this group gets a bar counter at all, and the default for
              every feed in it. Setting it false on a group of birthdays,
              holidays or sports fixtures mirrors them for the week view without
              ever putting a number on the bar.
            '';
          };

          feeds = lib.mkOption {
            default = { };
            description = ''
              The feeds in this group, keyed by a name that is unique across ALL
              groups — it names the directory under
              ~/.local/share/calendars and the khal calendar.
            '';
            type = lib.types.attrsOf (
              lib.types.submodule (
                { name, ... }:
                {
                  options = {
                    urlFile = lib.mkOption {
                      type = lib.types.str;
                      default = "${config.xdg.configHome}/vdirsyncer/${name}-url";
                      defaultText = lib.literalExpression ''"''${config.xdg.configHome}/vdirsyncer/‹name›-url"'';
                      description = ''
                        Path to a file containing nothing but this feed's URL.
                        Read at sync time via vdirsyncer's `url.fetch`, so the
                        link never enters the Nix store or git. Point it at a
                        sops secret to get it out of $HOME as well.
                      '';
                    };

                    label = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      defaultText = lib.literalMD "the attribute name";
                      description = ''
                        Name shown against individual events in the bar tooltip,
                        when its group has more than one feed. The attribute name
                        has to be terse and filesystem-safe; this does not.
                      '';
                    };

                    meetings = lib.mkOption {
                      type = lib.types.nullOr lib.types.bool;
                      default = null;
                      defaultText = lib.literalMD "the group's `meetings`";
                      description = ''
                        Override the group's `meetings` for this one feed — e.g.
                        an on-call rota that belongs with work but should not
                        inflate the count of things to attend.
                      '';
                    };
                  };
                }
              )
            );
          };
        };
      }
    );
  };

  # The resolved per-feed view, which is what everything downstream actually
  # wants: one entry per feed, carrying the group it came from and whether it
  # counts. Internal because it is derived, and shared so that the inheritance
  # rule for `meetings` (feed overrides group) exists in exactly ONE place
  # rather than once here and once in the bar module.
  options.my.calendarFeeds = lib.mkOption {
    type = lib.types.attrs;
    internal = true;
    default = feeds;
    description = "Flattened `my.calendars`, keyed by feed name.";
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
    # The flatten above is keyed by feed name, so a name reused in two groups
    # would silently lose one of them — and with it one vdir, one khal calendar
    # and one pair. Names are filesystem paths and khal identifiers, so they have
    # to be globally unique anyway; say so instead of debugging it later.
    assertions =
      let
        declared = lib.concatMap (group: lib.attrNames group.feeds) (lib.attrValues groups);
      in
      [
        {
          assertion = lib.length declared == lib.length (lib.unique declared);
          message =
            "my.calendars: feed names must be unique across groups, but got "
            + lib.concatStringsSep ", " (lib.sort (a: b: a < b) declared);
        }
      ];

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
      }) feeds;
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
    # One pair per FEED, flat — vdirsyncer has no notion of the groups; those
    # exist only to bucket the bar counters. Pairs sync independently and keep
    # per-pair status, so a feed whose link has gone stale (or whose urlFile is
    # missing) fails on its own and leaves the others alone: the service goes red,
    # and each counter's staleness follows the oldest feed IT counts.
    xdg.configFile."vdirsyncer/config".text = ''
      # Generated from `my.calendars` — edit that, not this file.
      # `collections = null` on every pair: a published ICS link is a single
      # calendar, not a discoverable set of collections, so there is nothing to
      # enumerate.
      [general]
      status_path = "${statusPath}"
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (name: feed: ''

        [pair ${name}]
        a = "${name}_local"
        b = "${name}_remote"
        collections = null

        [storage ${name}_local]
        type = "filesystem"
        path = "${vdirOf name}"
        fileext = ".ics"

        [storage ${name}_remote]
        type = "http"
        url.fetch = ["command", "cat", "${feed.urlFile}"]
      '') feeds
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
    # localhost CalDAV/webcal in front of the mirror, so GNOME Calendar reads the
    # SAME copy the bar counts. A user unit, not services.radicale: that NixOS
    # option runs as its own system user, which cannot read calendars living
    # under $HOME.
    systemd.user.services.radicale = {
      Unit = {
        Description = "Radicale, serving the local calendar mirror on localhost";
        After = [ "network.target" ];
      };
      Service = {
        ExecStart = "${pkgs.radicale}/bin/radicale --config ${radicaleConfig}";
        Restart = "on-failure";
        RestartSec = 5;
      };
      # default.target, not graphical-session: nothing here needs a display, and
      # khal/vdirsyncer work the same from a TTY.
      Install.WantedBy = [ "default.target" ];
    };

    # Two pieces of state that have to exist as real files rather than store
    # symlinks, hence activation rather than xdg.configFile:
    #   * .Radicale.props — radicale rewrites collection metadata in place.
    #   * the EDS .source files — evolution-data-server rewrites them when you
    #     recolour or hide a calendar in the UI, and a read-only symlink would
    #     make every such change fail silently.
    # The trade is the usual one for merged-not-owned config: delete a calendar
    # in GNOME Calendar and the next activation puts it back.
    home.activation.calendarCollections = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${collectionProps}

      sources="${config.xdg.configHome}/evolution/sources"
      run mkdir -p "$sources"
      ${lib.concatMapStringsSep "
" (src: ''
        target="$sources/${src.name}.source"
        want=${lib.escapeShellArg src.text}
        if [ ! -e "$target" ] || [ "$(cat "$target")" != "$want" ]; then
          printf '%s' "$want" > "$target"
          echo "calendar: subscribed GNOME Calendar to ${src.name} via radicale"
        fi
      '') edsSources}
    '';

    systemd.user.services.vdirsyncer.Service.ExecStartPre = [
      "${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArgs (map vdirOf (lib.attrNames feeds))}"
      "${config.services.vdirsyncer.package}/bin/vdirsyncer discover"
    ];
  };
}
