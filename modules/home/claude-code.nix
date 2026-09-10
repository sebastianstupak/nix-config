# Claude Code settings this machine owns.
#
# Only ONE key is managed here, and it is merged rather than written: Claude
# Code writes to ~/.claude/settings.json itself (theme, and the "you accepted
# this dialog" flags), so the usual xdg.configFile route would put a read-only
# store symlink where the app expects a writable file and every in-app settings
# change would fail. jq-merging one key leaves everything else — including keys
# added by future versions — untouched.
#
# Why the key matters here: notifications and the waybar workspace badge are
# different transports, and only one of them reaches the bar.
#
#   auto (the default)  Claude Code posts straight to D-Bus. swaync shows it,
#                       the terminal never learns anything, so no badge.
#   ghostty             routes it through the terminal, which then raises the
#                       notification itself — verified, the D-Bus sender becomes
#                       ghostty rather than Claude Code. Correct attribution,
#                       but raising a notification is not ringing a bell, so
#                       still no badge.
#   terminal_bell       writes BEL. ghostty's bell-features then mark the window
#                       title and raise attention, which is exactly what
#                       hyprland/workspaces window-rewrite counts (see
#                       modules/home/waybar.nix).
#
# Chosen over a Notification hook that shells out to write \a to the session's
# pty: that works (measured), but it is a custom script standing in for a
# supported setting, and it would need re-verifying on every Claude Code update.
{
  lib,
  pkgs,
  ...
}:
let
  notifChannel = "terminal_bell";
in
{
  home.activation.claudeCodeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    settings="$HOME/.claude/settings.json"
    mkdir -p "$(dirname "$settings")"
    [ -s "$settings" ] || echo '{}' > "$settings"

    tmp="$(mktemp)"
    if ${pkgs.jq}/bin/jq --arg c ${lib.escapeShellArg notifChannel} \
         '.preferredNotifChannel = $c' "$settings" > "$tmp" 2>/dev/null; then
      # Only replace on a successful parse+write. A half-written settings.json
      # would silently disable every setting in it, which is worse than not
      # applying this one.
      if ! ${pkgs.diffutils}/bin/cmp -s "$settings" "$tmp"; then
        mv "$tmp" "$settings"
        echo "claude-code: preferredNotifChannel set to ${notifChannel}"
      else
        rm -f "$tmp"
      fi
    else
      rm -f "$tmp"
      echo "claude-code: ~/.claude/settings.json is not valid JSON; left untouched" >&2
    fi
  '';
}
