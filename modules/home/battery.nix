# Low-battery warnings as desktop notifications.
#
# The thresholds are NOT declared here — they come from `my.power` in
# modules/nixos/power.nix via osConfig, so this toast, waybar's colour change
# and upower's action are three readings of one set of numbers. Changing a
# threshold in one place changes all three.
#
# A polling timer rather than a D-Bus subscription to upower. upower polls
# sysfs itself (every 30s), so listening to its signals buys no freshness, and
# it would mean parsing `upower --monitor-detail` output — a format with no
# stability promise — instead of reading two integers out of sysfs.
{
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  power = osConfig.my.power;

  monitor = pkgs.writeShellApplication {
    name = "battery-monitor";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.libnotify
    ];
    text = ''
      warn=${toString power.warnPercentage}
      crit=${toString power.criticalPercentage}
      action=${toString power.actionPercentage}
      # Quoted: the else branch is two words, and unquoted it would parse as an
      # assignment followed by a command called `off`.
      action_verb="${if power.hibernate.enable then "Hibernating" else "Powering off"}"

      # Charge summed across every battery present, so a machine with two
      # reports one figure rather than whichever /sys entry sorted first.
      #
      # energy_* (µWh) and charge_* (µAh) are the same ratio either way;
      # `capacity` is the kernel's own rounded percentage and the last resort.
      # Mixing units across batteries would be wrong, but a laptop with one
      # battery reporting energy and another reporting charge does not exist.
      now=0
      full=0
      for bat in /sys/class/power_supply/BAT*; do
        [ -d "$bat" ] || continue
        # A bay with no battery in it still has a sysfs directory.
        [ "$(cat "$bat/present" 2>/dev/null || echo 1)" = "1" ] || continue

        if [ -r "$bat/energy_now" ] && [ -r "$bat/energy_full" ]; then
          now=$(( now + $(cat "$bat/energy_now") ))
          full=$(( full + $(cat "$bat/energy_full") ))
        elif [ -r "$bat/charge_now" ] && [ -r "$bat/charge_full" ]; then
          now=$(( now + $(cat "$bat/charge_now") ))
          full=$(( full + $(cat "$bat/charge_full") ))
        elif [ -r "$bat/capacity" ]; then
          now=$(( now + $(cat "$bat/capacity") ))
          full=$(( full + 100 ))
        fi
      done

      # No battery at all: a desktop, or sysfs not populated yet. Not an error
      # — this module should be harmless on a machine without one.
      [ "$full" -gt 0 ] || exit 0

      pct=$(( (100 * now + full / 2) / full ))

      # Tier the current charge, so a notification fires once per threshold
      # CROSSED rather than once per minute spent below it. Without this the
      # 60s timer would repost the same toast twenty times on the way down.
      tier=0
      [ "$pct" -le "$warn" ] && tier=1
      [ "$pct" -le "$crit" ] && tier=2

      # Anything other than discharging resets the tiers, so unplugging again
      # later gives a fresh set of warnings. Checked per battery rather than
      # via the AC adapter: a dock can report online while the battery still
      # drains.
      charging=0
      for bat in /sys/class/power_supply/BAT*; do
        [ -r "$bat/status" ] || continue
        case "$(cat "$bat/status")" in
          Charging | Full | "Not charging") charging=1 ;;
        esac
      done

      state="''${XDG_RUNTIME_DIR:-/tmp}/battery-monitor.tier"
      last=0
      [ -r "$state" ] && read -r last < "$state"

      if [ "$charging" = "1" ] || [ "$tier" = "0" ]; then
        printf '0\n' > "$state"
        exit 0
      fi

      # Only ever escalate. Coming back UP a tier without charging (the kernel
      # revising its figures, which it does) must not re-arm a warning the
      # screen already showed.
      [ "$tier" -gt "$last" ] || exit 0

      if [ "$tier" = "2" ]; then
        urgency=critical
        icon=battery-caution
        summary="Battery critical — $pct%"
        body="$action_verb at $action%."
      else
        urgency=normal
        icon=battery-low
        summary="Battery low — $pct%"
        body="Plug in when you get the chance."
      fi

      # x-canonical-private-synchronous: the low toast is REPLACED by the
      # critical one instead of stacking under it, so the screen shows the
      # current state and not a history of it.
      #
      # State is written only if the notification was actually delivered. If
      # swaync is not up the tier stays un-fired and the next tick retries,
      # rather than silently marking a warning the screen never showed.
      if notify-send \
        --app-name=Battery \
        --urgency="$urgency" \
        --icon="$icon" \
        --hint=string:x-canonical-private-synchronous:battery \
        "$summary" "$body"; then
        printf '%s\n' "$tier" > "$state"
      fi
    '';
  };
in
{
  systemd.user.services.battery-monitor = {
    Unit = {
      Description = "Warn when the battery is low";
      # The notification needs a session to land in. Bound to the graphical
      # session rather than timers.target so it is not firing into nothing
      # from boot onwards — upower (modules/nixos/power.nix) is what covers
      # the machine when nobody is logged in.
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe monitor;
      # notify-send talks to the session bus. A user unit inherits this from
      # the manager environment in practice, but only because something ran
      # dbus-update-activation-environment first — spelling it out means the
      # warning does not depend on that having happened.
      Environment = [ "DBUS_SESSION_BUS_ADDRESS=unix:path=%t/bus" ];
    };
  };

  systemd.user.timers.battery-monitor = {
    Unit = {
      Description = "Check the battery level every minute";
      PartOf = [ "graphical-session.target" ];
    };
    Timer = {
      # A minute is fine: from the 20% warning there is over an hour of
      # runtime, and from 10% to the action at 7% is several minutes. Polling
      # harder would only cost wakeups on a machine that is trying to save
      # power.
      OnActiveSec = "1m";
      OnUnitActiveSec = "1m";
      Unit = "battery-monitor.service";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
