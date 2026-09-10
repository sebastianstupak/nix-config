# GNOME Calendar — the week view behind the waybar clock. Clicking the date at
# the top-left opens it (see the clock module in modules/home/waybar.nix); the
# backend it talks to is enabled in modules/nixos/desktop.nix.
#
# Chosen for the week view specifically: seven day columns, an hour grid, events
# drawn as blocks at their real times, and </> to step week by week. It is
# GTK4/libadwaita, so Stylix's GTK target themes it without extra work. Week
# starts Monday because of i18n.extraLocaleSettings.LC_TIME in
# modules/nixos/core.nix — the app has no first-day-of-week setting of its own.
#
# Subscribing to Proton Calendar is a MANUAL, one-time step, on purpose:
#   Proton (paid plans) mints a read-only ICS link per calendar under
#   Calendar -> Settings -> Share -> Share with anyone. Add it in GNOME Calendar
#   via Calendars -> Add Calendar -> From Web.
# That URL embeds the key that decrypts the calendar, so it is a secret. It is
# not in this repo because a string in a .nix file lands in git and in the
# world-readable /nix/store; typed into the app it stays in ~/.config/evolution.
#
# Why a subscription rather than sync: Proton exposes no CalDAV and no API (the
# bridge is mail-only), so an ICS feed is the whole integration surface. What
# that costs, all Proton-side and not fixable here:
#   - Read-only. New events are made in Proton's web app. If you want somewhere
#     writable, add a second local calendar in the app — that one syncs nowhere.
#   - Proton takes up to 8h to reflect an edit in the shared link, so there is
#     nothing to gain from tuning refresh intervals.
#   - The link expires in practice: Proton's own docs say to regenerate it and
#     resubscribe once third-party apps stop seeing updates.
#
# If "From Web" refuses the URL outright, that is gnome-calendar#142 — it sniffs
# for a .ics extension and Proton's link continues past calendar.ics into
# ?CacheKey=...&PassphraseKey=... . The fallback is a local CalDAV shim:
# vdirsyncer pulls the feed into radicale (both in nixpkgs) and the app
# subscribes to localhost, which has the side benefit of moving the secret into
# sops instead of ~/.config.
{ pkgs, ... }:
{
  home.packages = [ pkgs.gnome-calendar ];
}
