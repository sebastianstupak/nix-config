# Claude Code settings this machine owns: notification channel, plus a hook that
# rings the terminal bell.
#
# Settings are jq-MERGED, never written wholesale. Claude Code writes to
# ~/.claude/settings.json itself (theme, the "you accepted this dialog" flags),
# so an xdg.configFile would put a read-only store symlink where the app expects
# a writable file and every in-app settings change would fail. Merging leaves
# everything else — including keys added by future versions — untouched.
#
# The reason two mechanisms are needed at all: a desktop notification and the
# waybar workspace badge travel different transports, and no single channel
# feeds both. All three were measured on this machine:
#
#   auto (the default)  posts straight to D-Bus. swaync shows it, the terminal
#                       learns nothing, so no badge.
#   terminal_bell       writes BEL, so the badge fires — but it REPLACES the
#                       desktop notification rather than adding to it. The D-Bus
#                       Notify vanished entirely, taking the swaync popup and
#                       its entry in the notification centre with it.
#   ghostty             routes through the terminal, which raises the
#                       notification itself (the D-Bus sender becomes ghostty,
#                       not Claude Code). Keeps the notification, but raising a
#                       notification is not ringing a bell, so no badge.
#
# So: `ghostty` for the notification, and the hook below for the bell. The hook
# is the part that will need re-checking if Claude Code changes how hooks are
# spawned — the setting alone cannot do both.
{
  lib,
  pkgs,
  ...
}:
let
  # `ghostty`, not `terminal_bell`. Measured: terminal_bell does fire the badge,
  # but it REPLACES the desktop notification rather than adding to it — the
  # D-Bus Notify disappeared entirely, taking the swaync popup and its entry in
  # the notification centre with it. `ghostty` keeps the notification (raised by
  # the terminal, so it is attributed to ghostty), and the hook below supplies
  # the bell that terminal_bell would have given.
  notifChannel = "ghostty";

  # The bell the `ghostty` channel does not ring.
  #
  # Writing to /dev/tty is not an option: hooks are spawned without a
  # controlling terminal, so that open fails. Walk up instead — the hook's
  # ancestry runs through the Claude Code process, which does own the pty
  # (`.claude-wrapped` on /dev/pts/N), so the first ancestor with a tty is this
  # session's terminal. That makes the bell land on the right window even with
  # several sessions open, without the hook needing to know which it is.
  bellScript = pkgs.writeShellApplication {
    name = "claude-notify-bell";
    runtimeInputs = [
      pkgs.procps
      pkgs.coreutils
    ];
    text = ''
      # Hooks receive JSON on stdin; drain it so Claude Code never blocks on a
      # full pipe, and ignore it — the bell is the same for every notification.
      cat >/dev/null 2>&1 || true

      pid=$PPID
      # 12 is generous: the observed chain is hook -> shell -> claude, and a
      # bounded loop cannot spin if the tree is ever unexpected.
      for _ in $(seq 1 12); do
        [ -z "$pid" ] && break
        [ "$pid" = "1" ] && break
        tty=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
        case "$tty" in
          pts/*)
            printf '\a' > "/dev/$tty" 2>/dev/null || true
            exit 0
            ;;
        esac
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
      done
      # No pty found (a headless or piped session) — a missing bell is not worth
      # failing a hook over.
      exit 0
    '';
  };
in
{
  home.activation.claudeCodeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    settings="$HOME/.claude/settings.json"
    mkdir -p "$(dirname "$settings")"
    [ -s "$settings" ] || echo '{}' > "$settings"

    tmp="$(mktemp)"
    # The Notification array is rebuilt rather than appended to: entries whose
    # command mentions this script are dropped first, so re-running (or a
    # rebuild that changes the store path) replaces our entry instead of
    # stacking a second copy — while any hook the user added themselves is
    # carried through untouched.
    if ${pkgs.jq}/bin/jq \
         --arg c ${lib.escapeShellArg notifChannel} \
         --arg cmd ${lib.escapeShellArg "${bellScript}/bin/claude-notify-bell"} \
         '.preferredNotifChannel = $c
          | .hooks.Notification =
              (((.hooks.Notification // [])
                | map(select(
                    ([.hooks[]?.command // ""] | any(test("claude-notify-bell"))) | not
                  )))
               + [{ hooks: [ { type: "command", command: $cmd } ] }])' \
         "$settings" > "$tmp" 2>/dev/null; then
      # Only replace on a successful parse+write. A half-written settings.json
      # would silently disable every setting in it, which is worse than not
      # applying this one.
      if ! ${pkgs.diffutils}/bin/cmp -s "$settings" "$tmp"; then
        mv "$tmp" "$settings"
        echo "claude-code: notif channel ${notifChannel} + bell hook applied"
      else
        rm -f "$tmp"
      fi
    else
      rm -f "$tmp"
      echo "claude-code: ~/.claude/settings.json is not valid JSON; left untouched" >&2
    fi
  '';
}
