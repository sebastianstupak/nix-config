# Calendar. Two consumers of one Proton Calendar feed:
#   - GNOME Calendar for the week view, opened by clicking the waybar clock.
#   - khal for the "meetings left today" counter in the bar (the script that
#     reads it lives with the other bar scripts, in modules/home/waybar.nix).
#
# Proton exposes no CalDAV and no API — the mail bridge is mail-only — so a
# shared ICS link is the entire integration surface, and everything here is
# read-only. New events get made in Proton's web app; if you want somewhere
# writable, add a second, local calendar inside GNOME Calendar.
#
#   Proton share link ──vdirsyncer, every 30 min──▶ ~/.local/share/calendars
#                    │                                      └─▶ khal ─▶ waybar
#                    └──GNOME Calendar's own web subscription──▶ week view
#
# The two fetch the feed independently, on purpose. GNOME Calendar can only
# subscribe to a URL, and nothing can query the copy inside evolution-data-server
# from a shell script, so a bar counter needs its own local mirror either way.
# The duplicate GET is a few KB against a feed Proton only refreshes every ~8h;
# the alternative — running radicale as a local CalDAV server so both read one
# mirror — is a daemon and a pile of moving parts for the same two numbers.
#
# TWO MANUAL STEPS, once per machine. Neither can live in the repo, because the
# share link embeds the key that decrypts the calendar:
#
#   1. Mint the link: Proton Calendar ▸ Settings ▸ Share ▸ Share with anyone
#      (paid plans only), then drop it where vdirsyncer can read it:
#        install -m600 /dev/stdin ~/.config/vdirsyncer/proton-url <<< '<link>'
#      Once secrets/ is wired up, point urlFile at the sops path instead and
#      this step disappears.
#   2. Paste the same link into GNOME Calendar: Calendars ▸ Add Calendar ▸
#      From Web. If it refuses the URL outright that is gnome-calendar#142 — it
#      sniffs for a .ics extension and Proton's link continues past
#      calendar.ics into ?CacheKey=...&PassphraseKey=... .
#
# The week view starts on Monday because of i18n.extraLocaleSettings.LC_TIME in
# modules/nixos/core.nix; GNOME Calendar has no first-day-of-week setting of its
# own. The backend it talks to is enabled in modules/nixos/desktop.nix.
{
  config,
  pkgs,
  ...
}:
let
  # Everything below, and the waybar counter, derives its paths from these two
  # options rather than repeating literals — so the bar cannot end up reading a
  # different directory than vdirsyncer writes.
  inherit (config.accounts.calendar) basePath;
  vdir = config.accounts.calendar.accounts.proton.local.path;

  # Kept under basePath rather than in vdirsyncer's usual $XDG_DATA_HOME spot so
  # that the bar script can find it from `accounts.calendar` alone: vdirsyncer
  # rewrites proton.items on every successful sync — even a no-op one — which
  # makes its mtime the honest "last synced" marker for the stale indicator.
  statusPath = "${basePath}/.vdirsyncer-status";

  urlFile = "${config.xdg.configHome}/vdirsyncer/proton-url";
in
{
  home.packages = [ pkgs.gnome-calendar ];

  accounts.calendar = {
    basePath = "${config.xdg.dataHome}/calendars";
    accounts.proton = {
      primary = true;
      # local.{type,path,fileExt} default to filesystem / basePath/proton /
      # ".ics", which is exactly the vdir khal wants.
      #
      # `remote` is deliberately left null even though there IS a remote: the
      # framework can only express the feed URL as a plain string, and that
      # string would land in git and in the world-readable store. The
      # hand-written vdirsyncer config below is the whole reason why.
      khal = {
        enable = true;
        type = "calendar";
      };
    };
  };

  programs.khal = {
    enable = true;

    # These formats are load-bearing, not cosmetic. The waybar counter asks khal
    # for each event's `end` and compares it against `date` output as a STRING to
    # decide what is still ahead, so the format has to be zero-padded and
    # big-endian to sort correctly. Anything locale-shaped would break that the
    # moment LC_TIME changes — and it just did (core.nix).
    #
    # Timezones are left unset: khal falls back to the system zone, which
    # time.timeZone already pins. Naming Europe/Bratislava here too would just be
    # a second copy to keep in step.
    locale = {
      dateformat = "%Y-%m-%d";
      longdateformat = "%Y-%m-%d";
      timeformat = "%H:%M";
      datetimeformat = "%Y-%m-%d %H:%M";
      longdatetimeformat = "%Y-%m-%d %H:%M";
    };
  };

  # Hand-written instead of generated from accounts.calendar, for the one reason
  # given above: `url.fetch` keeps the share link out of the store, and the HM
  # framework has no option that emits it. The mechanism is undocumented but
  # real — vdirsyncer's Config.get_storage_args runs expand_fetch_params over
  # every storage section, and that strips a `.fetch` suffix off ANY key, not
  # just password (strategies: command, shell, prompt).
  xdg.configFile."vdirsyncer/config".text = ''
    [general]
    status_path = "${statusPath}"

    [pair proton]
    a = "proton_local"
    b = "proton_remote"
    # A shared ICS link is a single calendar, not a discoverable set of
    # collections, so there is nothing to enumerate.
    collections = null

    [storage proton_local]
    type = "filesystem"
    path = "${vdir}"
    fileext = ".ics"

    [storage proton_remote]
    type = "http"
    url.fetch = ["command", "cat", "${urlFile}"]
  '';

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
  #     when the local collection directory is missing — and a systemd unit
  #     answers prompts with EOF, i.e. N, i.e. nothing ever gets created.
  # Creating the directory first turns discover into a silent no-op, so it is
  # safe to re-run ahead of every sync.
  systemd.user.services.vdirsyncer.Service.ExecStartPre = [
    "${pkgs.coreutils}/bin/mkdir -p ${vdir}"
    "${config.services.vdirsyncer.package}/bin/vdirsyncer discover"
  ];
}
