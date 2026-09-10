# Waybar: the Hyprland status bar. Split out of hyprland.nix because the bar's
# module/style config is bigger than the compositor's.
#
# Why this file exists at all: `programs.waybar.enable = true` alone writes NO
# config, so waybar falls back to the upstream default (/etc/xdg/waybar/config),
# which is written for Sway. Under Hyprland every `sway/*` module in it silently
# does nothing — meaning no workspaces and no keyboard-layout indicator (the
# latter matters here: kb_options = grp:alt_shift_toggle switches us <-> sk with
# zero visual feedback). The default also carries modules
# that can't work on this machine: mpd, custom/media (points at a mediaplayer.py
# that doesn't exist), battery#bat2, and power-profiles-daemon — which laptop.nix
# explicitly disables in favour of TLP.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Scheme colors for the CPU/RAM thresholds, so green/amber/red stay in the
  # Kanagawa Dragon palette instead of being raw #00ff00-style values that clash
  # with everything else on the bar.
  colors = config.lib.stylix.colors;

  # Feeds custom/perf. A script rather than waybar's built-in cpu/memory modules
  # because those cannot answer "which process?" — their tooltip formats expose
  # only aggregate placeholders ({usage}, {load}, {percentage}), with no hook for
  # a process list. One module also beats two: cpu+memory would need two separate
  # hovers to answer one question.
  #
  # writeShellApplication, not writeShellScript: it runs shellcheck at build time
  # and puts runtimeInputs on PATH, so a typo here fails `nixos-rebuild build`
  # instead of silently blanking the module at runtime.
  perfScript = pkgs.writeShellApplication {
    name = "waybar-perf";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.procps
      pkgs.gawk
      pkgs.jq
      pkgs.gnused
    ];
    text = ''
      state="''${XDG_RUNTIME_DIR:-/tmp}/waybar-perf.state"

      # CPU% across the interval since the previous run, from /proc/stat deltas.
      # A point-in-time reading is impossible — /proc/stat holds monotonic
      # counters since boot, so the alternatives are sleeping mid-script (stalls
      # the bar for the whole interval) or reporting a since-boot average (which
      # barely moves). Carrying the previous totals in a state file costs nothing
      # and makes the number mean "over the last 5s".
      read -r _ user nice sys idle iowait irq softirq steal _ < /proc/stat
      total=$(( user + nice + sys + idle + iowait + irq + softirq + steal ))
      idle_all=$(( idle + iowait ))

      # 0 on the very first run only: there is no previous sample to diff yet.
      cpu=0
      if [ -r "$state" ]; then
        read -r prev_total prev_idle < "$state"
        d_total=$(( total - prev_total ))
        d_idle=$(( idle_all - prev_idle ))
        # +d_total/2 rounds to nearest instead of truncating.
        if [ "$d_total" -gt 0 ]; then
          cpu=$(( (100 * (d_total - d_idle) + d_total / 2) / d_total ))
        fi
      fi
      printf '%s %s\n' "$total" "$idle_all" > "$state"

      # MemAvailable, not MemFree: MemFree excludes reclaimable page cache and so
      # reads as ~100% used on any machine that has been up a while.
      read -r mem_pct mem_used mem_total swap_pct <<< "$(
        awk '
          /^MemTotal:/     { t  = $2 }
          /^MemAvailable:/ { a  = $2 }
          /^SwapTotal:/    { st = $2 }
          /^SwapFree:/     { sf = $2 }
          END {
            printf "%d %.1f %.1f %d",
              (t - a) * 100 / t, (t - a) / 1048576, t / 1048576,
              (st > 0 ? (st - sf) * 100 / st : 0)
          }
        ' /proc/meminfo
      )"

      read -r load1 load5 load15 _ < /proc/loadavg

      # CPU and RAM are coloured INDEPENDENTLY, which is why this is inline pango
      # markup rather than a CSS class: `class` styles the whole module, so it can
      # only ever express one combined state — a pegged CPU next to idle RAM would
      # turn both red. waybar renders label markup via set_markup (custom.cpp),
      # so per-metric <span color> works here.
      warn_at=70
      crit_at=90
      color_for() {
        if [ "$1" -ge "$crit_at" ]; then
          printf '#${colors.base08}' # red
        elif [ "$1" -ge "$warn_at" ]; then
          printf '#${colors.base0A}' # amber
        else
          printf '#${colors.base0B}' # green
        fi
      }
      cpu_color=$(color_for "$cpu")
      mem_color=$(color_for "$mem_pct")

      # Tooltips are pango markup, so a process called "foo&bar" would silently
      # break the whole tooltip. Escape & first, or it would re-escape its own
      # output from the later substitutions.
      esc() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }

      # comm can contain spaces, so glue $3..NF back together rather than taking
      # $3 alone and truncating the name.
      top_by() {
        ps -eo pcpu=,pmem=,comm= --sort="-$1" | head -n 5 | awk '
          { cmd = $3; for (i = 4; i <= NF; i++) cmd = cmd " " $i
            printf "  %5.1f%%  %5.1f%%  %s\n", $1, $2, cmd }
        ' | esc
      }

      # Same colours in the tooltip header, so hovering confirms what the bar
      # colour is telling you rather than restating it in plain grey.
      tooltip=$(printf '<b>CPU</b>  <span color="%s"><b>%s%%</b></span>   load %s %s %s\n<b>RAM</b>  <span color="%s"><b>%s%%</b></span>  %s / %s GiB   swap %s%%\n\n<tt><b>  cpu     ram   top by CPU</b>\n%s</tt>\n<tt><b>  cpu     ram   top by RAM</b>\n%s</tt>\n<i>Click for btop</i>' \
        "$cpu_color" "$cpu" "$load1" "$load5" "$load15" \
        "$mem_color" "$mem_pct" "$mem_used" "$mem_total" "$swap_pct" \
        "$(top_by pcpu)" "$(top_by pmem)")

      text=$(printf '<span color="%s">󰻠 %s%%</span>  <span color="%s">󰍛 %s%%</span>' \
        "$cpu_color" "$cpu" "$mem_color" "$mem_pct")

      # Still emitted for CSS that wants to react to the module as a whole (a
      # background, a border) — but NOT for colour, which the spans above own per
      # metric. Worst-of-the-two, so it escalates when either one does.
      class=ok
      if [ "$cpu" -ge "$crit_at" ] || [ "$mem_pct" -ge "$crit_at" ]; then
        class=critical
      elif [ "$cpu" -ge "$warn_at" ] || [ "$mem_pct" -ge "$warn_at" ]; then
        class=warning
      fi

      # jq builds the JSON so newlines/quotes/markup in the tooltip are escaped
      # correctly — hand-rolled printf JSON breaks the moment a process name has
      # a quote in it.
      jq -cn --arg t "$text" --arg tip "$tooltip" --arg c "$class" \
        '{text: $t, tooltip: $tip, class: $c}'
    '';
  };

  # Feeds custom/clock. A script rather than waybar's built-in `clock`, which
  # cannot label a world clock: with `timezones` set, its {tz_list} runs every
  # zone through ONE shared format string and emits no zone name (see
  # getTZtext() in waybar's clock.cpp). Bali and Singapore are both UTC+8, so
  # that tooltip would render two identical rows and a third that repeats local
  # time — and Singapore's %Z is the unhelpful "+08", not "SGT".
  #
  # Ticking is handled the same way the built-in module does it — on the minute
  # boundary — by running as a long-lived script that sleeps to the next :00
  # rather than being re-executed on an `interval` phase-aligned to whenever
  # waybar started. The one thing genuinely lost is the built-in calendar
  # widget's month scrolling; `cal` draws the same grid, statically.
  clockScript = pkgs.writeShellApplication {
    name = "waybar-clock";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux # cal
      pkgs.gnused
      pkgs.jq
    ];
    text = ''
      # Pinned rather than inherited. glibc resolves TZ against $TZDIR, and when
      # it cannot find the zone file it does NOT fail — it parses "Asia/Makassar"
      # as a POSIX TZ spec, yielding UTC with %Z as the literal "Asia". Every row
      # would then quietly agree with the local clock. The session does export
      # TZDIR=/etc/zoneinfo today, but a wrong world clock is invisible in a way
      # a missing one is not, so don't depend on the ambient value.
      export TZDIR=${pkgs.tzdata}/share/zoneinfo

      # label:zone. Bali has no zone of its own — Asia/Makassar IS Indonesia
      # Central (WITA), which is Bali. Slovenia sits on the same offset as
      # Europe/Bratislava, so its row always mirrors the local time; it is here
      # to be read by name, not because it ever differs.
      zones=(
        "Bali:Asia/Makassar"
        "Singapore:Asia/Singapore"
        "Slovenia:Europe/Ljubljana"
      )

      # Offsets as minutes east of UTC, so the delta stays right for half-hour
      # and 45-minute zones as well. None of the three need that today, but a
      # wrong number here would look plausible rather than obviously broken.
      off_min() {
        local o=$1 sign=1
        [ "''${o:0:1}" = "-" ] && sign=-1
        echo $(( sign * (10#''${o:1:2} * 60 + 10#''${o:3:2}) ))
      }
      # Everything below is recomputed per tick, inside a function, because this
      # module is long-running rather than re-executed (see the loop at the end).
      emit() {
        local_min=$(off_min "$(date +%z)")

      # %a matters as much as the time: at +6h, Bali is already tomorrow for a
      # good chunk of the local evening, and a bare 04:33 hides that.
      lines=()
      for entry in "''${zones[@]}"; do
        label=''${entry%%:*}
        read -r dow hhmm off <<< "$(TZ="''${entry#*:}" date '+%a %H:%M %z')"

        delta=$(( $(off_min "$off") - local_min ))
        if [ "$delta" -eq 0 ]; then
          rel="±0"
        else
          sign=+
          if [ "$delta" -lt 0 ]; then
            sign=-
            delta=$(( -delta ))
          fi
          rel="$sign$(( delta / 60 ))h"
          [ $(( delta % 60 )) -ne 0 ] && rel="$rel$(( delta % 60 ))"
        fi

        lines+=( "$(printf '%-10s %s %s  %s' "$label" "$dow" "$hhmm" "$rel")" )
      done

      # -m forces Monday-first instead of trusting LC_TIME to reach a systemd
      # user unit, so this grid cannot disagree with GNOME Calendar's week view.
      # \b around the day number is what keeps the bolding off "2026" and off
      # the 1 inside 10; the trailing all-blank lines cal pads with are dropped
      # so the tooltip doesn't grow a gap.
      today=$(date +%-d)
      grid=$(cal -m | sed -E "s/\b$today\b/<b>$today<\/b>/; /^[[:space:]]*$/d")

      # <tt> on both blocks: pango's default font is proportional, so the
      # columns above would only line up by accident without it.
      tooltip=$(printf '<b>%s</b>\n\n<tt>%s</tt>\n\n<tt>%s</tt>\n\n<i>Click for the week view</i>' \
        "$(date '+%A, %Y-%m-%d')" "$grid" "$(printf '%s\n' "''${lines[@]}")")

      jq -cn --arg t "$(date '+%H:%M %Z  %Y/%m/%d')" --arg tip "$tooltip" \
          '{text: $t, tooltip: $tip}'
      }

      # Long-running, one JSON line per update — NOT a script waybar re-runs on
      # an `interval`. An interval is phase-aligned to whenever waybar started,
      # so it flips the minute up to a whole interval late: with 60s the clock
      # was routinely a minute behind, and even 10s meant the digit changed when
      # waybar felt like it rather than when the minute did. Sleeping to the
      # boundary instead makes the clock change exactly when the clock changes,
      # and costs one process for the session instead of one every few seconds.
      while true; do
        emit
        # 10# forces base 10: `date +%S` renders eight seconds past as "08",
        # which the shell would otherwise reject as invalid octal.
        sleep $(( 60 - 10#$(date +%S) ))
      done
    '';
  };

  # Click target for systemd-failed-units. The module itself renders only a
  # count — it never calls set_tooltip, so a `tooltip-format` on it would not be
  # populated — and a bare count cannot tell you WHICH unit died. Lists both
  # managers because the module counts both.
  failedUnitsScript = pkgs.writeShellApplication {
    name = "waybar-failed-units";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      printf '=== system units ===\n'
      systemctl --failed --no-pager || true
      printf '\n=== user units ===\n'
      systemctl --user --failed --no-pager || true
      printf '\nReset a stuck one with:  systemctl [--user] reset-failed <unit>\n'
      printf '\nPress enter to close.\n'
      # EOF (no tty) would make read fail, and set -e would kill the window
      # before anything could be read.
      read -r _ || true
    '';
  };

  # Click target for the backlight module: toggles the night light (warm screen).
  #
  # Talks to the hyprsunset daemon over hyprctl rather than starting and killing
  # the process, because a pkill toggle depends on hyprsunset restoring the colour
  # transform matrix on the way out — if it is ever killed hard, or dies, the
  # screen stays tinted with nothing left running to fix it. The daemon (started
  # --identity in hyprland.nix) always owns the CTM, and this only sends requests.
  #
  # State lives in a file because hyprsunset exposes no way to ask what
  # temperature is currently applied, so the toggle has to remember. Kept in
  # XDG_RUNTIME_DIR so a reboot resets it to "off", which matches the daemon
  # coming back up at identity.
  nightLightScript = pkgs.writeShellApplication {
    name = "waybar-nightlight";
    # hyprctl is deliberately NOT vendored here. Adding pkgs.hyprland would pull
    # a second copy of the compositor into the closure and hand this script an
    # hyprctl from a possibly different version than the one running — the exact
    # trap `package = null` avoids at the top of hyprland.nix. writeShellApplication
    # keeps the inherited PATH (inheritPath defaults true), so this resolves
    # /run/current-system/sw/bin/hyprctl: the system Hyprland's own.
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      state="''${XDG_RUNTIME_DIR:-/tmp}/hyprsunset.state"

      if [ "$(cat "$state" 2>/dev/null)" = "on" ]; then
        hyprctl hyprsunset identity
        printf 'off\n' > "$state"
      else
        # 3500K: clearly warm without going orange enough to make syntax
        # highlighting unreadable. 4000-4500 is subtler, 2500 is candlelight.
        hyprctl hyprsunset temperature 3500
        printf 'on\n' > "$state"
      fi
    '';
  };

  # Feeds custom/vpn. Shows a tunnel only while one is actually up, and hides
  # itself otherwise — the `network` module already covers plain connectivity, so
  # a permanent "VPN: off" chip would be clutter. Flip the early-exit below if you
  # would rather see an explicit off state.
  vpnScript = pkgs.writeShellApplication {
    name = "waybar-vpn";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.iproute2
      pkgs.jq
    ];
    text = ''
      # Match on kernel device TYPE, not interface name. NetBird uses wt0,
      # ProtonVPN's WireGuard and OpenVPN modes use different names again, and a
      # name-prefix match would silently miss whichever one is renamed next.
      # WireGuard links sit at operstate UNKNOWN rather than UP — filtering on UP
      # alone reports every WireGuard tunnel as down.
      tunnels=$(
        {
          ip -j link show type wireguard 2>/dev/null || echo '[]'
          ip -j link show type tun 2>/dev/null || echo '[]'
        } | jq -s -r 'add // [] | .[]
              | select(.operstate == "UP" or .operstate == "UNKNOWN")
              | .ifname' | sort -u
      )

      if [ -z "$tunnels" ]; then
        # Empty text hides a custom module.
        jq -cn '{text: "", tooltip: ""}'
        exit 0
      fi

      # Interface names are not self-explanatory (wt0 means nothing at a glance),
      # so map the ones this machine can produce onto readable labels.
      label_for() {
        case "$1" in
          wt* | nb-*) printf 'NetBird' ;;
          proton* | pvpn*) printf 'Proton' ;;
          wg*) printf 'WireGuard' ;;
          *) printf 'VPN' ;;
        esac
      }

      count=$(printf '%s\n' "$tunnels" | wc -l)
      first=$(printf '%s\n' "$tunnels" | head -n 1)
      if [ "$count" -eq 1 ]; then
        text="󰦝 $(label_for "$first")"
      else
        text="󰦝 $count tunnels"
      fi

      tip=""
      while read -r i; do
        [ -n "$i" ] || continue
        addrs=$(ip -j addr show dev "$i" 2>/dev/null |
          jq -r '.[0].addr_info[]? | select(.family == "inet") | .local' |
          paste -sd' ' -)
        tip="$tip$(label_for "$i")  ($i)''${addrs:+  $addrs}
      "
      done <<< "$tunnels"

      jq -cn --arg t "$text" --arg tip "$tip" '{text: $t, tooltip: ($tip | rtrimstr("\n"))}'
    '';
  };

  # One counter per calendar group, built from `my.calendars` +
  # `my.calendarGroups` — the same attrsets home/<user>/default.nix declares, so
  # the bar and the syncer cannot disagree, and a calendar name khal does not
  # know is impossible by construction (khal validates -a against its own config
  # and aborts with a usage error, which the module's error state would surface).
  meetingGroups =
    let
      # my.calendarFeeds is the resolved flat view calendar.nix exports: one
      # entry per feed, carrying its group's icon/order and whether it counts.
      # Reading that rather than re-walking my.calendars keeps the
      # feed-overrides-group rule for `meetings` in one place.
      counted = lib.filterAttrs (_: f: f.meetings) config.my.calendarFeeds;
      inGroup = g: lib.filterAttrs (_: f: f.group == g) counted;
    in
    lib.sort (a: b: if a.order == b.order then a.group < b.group else a.order < b.order) (
      map (
        g:
        let
          members = inGroup g;
        in
        {
          group = g;
          # Every feed in a group carries the same icon/order, so any member does.
          inherit (lib.head (lib.attrValues members)) icon order;
          calendars = lib.attrNames members;
          labels = lib.mapAttrs (_: f: f.label) members;
        }
      ) (lib.unique (lib.mapAttrsToList (_: f: f.group) counted))
    );

  # Feeds one custom/meetings-<group> module: how many of that group's meetings
  # are still ahead today. modules/home/calendar.nix owns how the feeds get here.
  #
  # khal rather than reading the .ics files here: a vdir holds raw VEVENTs, so
  # anything hand-rolled would have to expand RRULEs and resolve VTIMEZONEs
  # itself — a daily standup would either vanish or show up once, in 2019. khal
  # does both already, and `--json` (0.14+) hands back fields instead of the
  # human table that older waybar recipes scrape with awk. It also drops
  # STATUS:CANCELLED events on its own, which matters for Outlook feeds: they
  # keep carrying cancelled meetings, and none of them reach the count.
  meetingsScriptFor =
    grp:
    pkgs.writeShellApplication {
      name = "waybar-meetings-${grp.group}";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.khal
        pkgs.jq
      ];
      text = ''
        calendars=(${lib.escapeShellArgs grp.calendars})
        status_dir=${lib.escapeShellArg config.my.calendarStatusPath}

        # Freshness comes from the OLDEST calendar in the group, and names it: a
        # count merged from several feeds is only as trustworthy as its worst
        # source, and each pair fails independently — an Outlook link the tenant
        # rotated stops updating while Proton carries on, which without this
        # would look like a quiet Thursday. With several feeds behind one
        # counter, "20h behind" is not actionable unless it says WHICH one.
        #
        # vdirsyncer rewrites these on every successful sync including no-op
        # ones, so mtime is the real "last synced".
        oldest=""
        oldest_cal=""
        for c in "''${calendars[@]}"; do
          f="$status_dir/$c.items"
          if [ ! -f "$f" ]; then
            oldest=""
            oldest_cal="$c"
            break
          fi
          m=$(stat -c %Y "$f")
          if [ -z "$oldest" ] || [ "$m" -lt "$oldest" ]; then
            oldest=$m
            oldest_cal="$c"
          fi
        done

        stale=no
        if [ -n "$oldest" ]; then
          mins=$(( ( $(date +%s) - oldest ) / 60 ))
          # Switch to hours past a couple of them, because the number people
          # actually read this tooltip for is "is 1200 minutes bad?".
          if [ "$mins" -ge 120 ]; then
            synced="$(( mins / 60 ))h ago"
          else
            synced="$mins min ago"
          fi
          [ "$mins" -gt 720 ] && stale=yes
        else
          synced="never"
          stale=yes
        fi

        # -a restricts the query to THIS group's calendars; without it khal would
        # merge in every mirrored feed — the other group's, plus birthdays and
        # holidays. `today 1d` means today ONLY: the range argument is a length,
        # not an end date. Fields rather than a format string so the filter below
        # can read them; khal accepts --json repeatedly.
        args=()
        for c in "''${calendars[@]}"; do args+=(-a "$c"); done

        if ! events=$(khal list "''${args[@]}" \
          --json title --json calendar --json start-time \
          --json end-time --json end today 1d 2>&1); then
          jq -cn --arg icon ${lib.escapeShellArg grp.icon} --arg err "$events" \
            '{text: "\($icon) ?", tooltip: ("khal could not read the calendars:\n" + $err),
              class: "error"}'
          exit 0
        fi

        # Filtering on `end`, not `start`: a meeting you are sitting in is still
        # one of today's meetings, and --notstarted is no help — it filters
        # against the START of the range (00:00 today), so it keeps everything.
        # `end` carries the date as well as the time, which also gets the 23:45
        # event ending at 00:00 right; comparing bare clock times would drop it.
        #
        # All-day entries are excluded by the empty start-time: they are not
        # meetings, and counting them would put a permanent +1 on the bar.
        #
        # group_by over (start, end, title) DEDUPES one meeting arriving on two
        # feeds in the same group — invited on your mailbox calendar AND sitting
        # on the shared team calendar is one thing to attend, not two. It cannot
        # key on UID: vdirsyncer's http storage REWRITES every UID to a content
        # hash on the way into the vdir (verified — an Outlook
        # UID:040000008200E000... arrives as UID:1cb18063...), and two feeds
        # carry different bytes for the same meeting, so their hashes differ.
        # The cost is that two genuinely different meetings sharing a title AND
        # a time slot collapse to one, which for a count of things you can
        # attend is the right answer anyway.
        #
        # sort_by(.end) afterwards: khal returns events grouped per calendar, so
        # a merged list would otherwise read 09:00, 14:00, 10:00 — useless as a
        # "what's next" list, which is the whole point of the hover.
        jq -cn --argjson evs "$events" --arg now "$(date '+%Y-%m-%d %H:%M')" \
          --arg synced "$synced" --arg stalecal "$oldest_cal" --arg stale "$stale" \
          --arg icon ${lib.escapeShellArg grp.icon} \
          --arg group ${lib.escapeShellArg grp.group} \
          --argjson labels ${lib.escapeShellArg (builtins.toJSON grp.labels)} \
          --argjson showcal ${if lib.length grp.calendars > 1 then "true" else "false"} '
          def esc: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
          [ $evs[] | select(."start-time" != "" and .end > $now) ]
          | group_by([ .["start-time"], .end, .title ])
          | map(.[0])
          | sort_by(.end) as $left
          | ($left | length) as $n
          | {
              text: "\($icon) \($n)",
              tooltip: (
                "<b>\($group) — "
                + (if $n == 0 then "nothing left today" else "\($n) left today" end)
                + "</b>"
                + (if $n == 0 then ""
                   else "\n"
                        + ([ $left[]
                             | "  \(."start-time")–\(."end-time")  \(.title | esc)"
                               + (if $showcal
                                  then "  <i>\(($labels[.calendar] // .calendar) | esc)</i>"
                                  else "" end) ]
                           | join("\n"))
                   end)
                + (if $stale == "yes"
                   then "\n<i>\($stalecal) synced \($synced) — check systemctl --user status vdirsyncer</i>"
                   else "\n<i>Synced \($synced)</i>" end)
              ),
              class: (if $stale == "yes" then "stale" elif $n == 0 then "none" else "ok" end),
            }'
      '';
    };

  # `#custom-meetings-work, #custom-meetings-personal` and so on: waybar names a
  # custom module's node after the module, so per-group counters mean per-group
  # selectors, which means the rules have to be generated alongside them.
  meetingSelectors =
    suffix: lib.concatMapStringsSep ",\n" (grp: "#custom-meetings-${grp.group}${suffix}") meetingGroups;

  meetingCss = lib.optionalString (meetingGroups != [ ]) ''
    ${meetingSelectors ""} {
      padding: 0 5px;
    }
    ${meetingSelectors ".none"} {
      color: @base04;
    }
    ${meetingSelectors ".stale"} {
      color: @base0A;
    }
    ${meetingSelectors ".error"} {
      color: @base08;
    }
  '';
in
{
  programs.waybar = {
    enable = true;

    # Run as a user unit rather than a hyprland exec-once. Besides
    # Restart=on-failure and ConditionEnvironment=WAYLAND_DISPLAY, the practical
    # win is that HM stamps the generated config.json and style.css as
    # X-Reload-Triggers with ExecReload=kill -SIGUSR2 — so `nixos-rebuild switch`
    # reloads the bar in place instead of leaving a stale one running.
    #
    # This reaches its target because HM's hyprland module defines
    # hyprland-session.target with BindsTo=graphical-session.target (and the
    # generated hyprland.conf starts it), so graphical-session.target — what the
    # waybar unit is WantedBy — is actually activated.
    systemd.enable = true;

    settings.main = {
      layer = "top";
      position = "top";
      # No `height`: waybar auto-sizes from the CSS below, which keeps the bar
      # in step with the Stylix font size instead of needing a matching tweak.
      spacing = 6;

      # Left holds the two things worth reading mid-task (date/time, now playing),
      # workspaces sit dead centre, and the right edge is the status cluster.
      # `modules-center` is a real centre: waybar puts it in a GTK centre box, so
      # it stays put regardless of how wide the left and right groups get.
      #
      # Deliberately NO `hyprland/window` module. The focused window's title is
      # ghostty's job to show — see window-decoration in modules/home/terminal.nix.
      # Duplicating it here just meant reading the same "claude"/cwd string in two
      # places, and a centred title fights the workspaces for the same space.
      modules-left = [
        "custom/clock"
      ]
      # One counter per calendar group, in `my.calendarGroups.<g>.order`. A group
      # with nothing flagged `meetings = true` produces no module at all, rather
      # than a permanent "󰃭 0" — with no -a arguments khal would happily count
      # every mirrored feed instead of none, so "no counted calendars" has to
      # mean "no counter", not "count everything".
      ++ map (grp: "custom/meetings-${grp.group}") meetingGroups
      ++ [
        "custom/notification"
        "mpris"
      ];
      modules-center = [ "hyprland/workspaces" ];
      modules-right = [
        # Both of these self-hide when there is nothing to say, so they cost no
        # space until they matter — hence the prime position at the near edge.
        "systemd-failed-units"
        # A live mic or screenshare lands as far from the busy status cluster as
        # possible. Self-hides when nothing is capturing.
        "privacy"
        # perf and temperature adjacent: both answer "is this machine struggling",
        # and both use the same green/amber/red scale.
        "custom/perf"
        "temperature"
        "tray"
        "idle_inhibitor"
        "hyprland/language"
        "backlight"
        "wireplumber"
        "bluetooth"
        # Next to `network`, since it qualifies what that module is telling you.
        "custom/vpn"
        "network"
        "battery"
        "custom/power"
      ];

      "hyprland/workspaces" = {
        # `{windows}` renders one glyph per window in the workspace, via the
        # window-rewrite rules below. Everything rewrites to nothing except
        # windows asking for attention, so a workspace shows its number alone
        # until something there wants you — then it grows one bell per waiting
        # window, which IS the count.
        format = "{name}{windows}";
        on-click = "activate";

        # How a terminal app ends up here: Claude Code (or any program) writes
        # BEL, ghostty's default bell-features includes `title`, so it prefixes
        # the window title with 🔔 and holds it until the window is focused.
        # Verified on this machine — the title genuinely becomes
        # "🔔 ✳ Improve waybar functionality".
        #
        # This counts ghostty WINDOWS, not panes, and only reflects each
        # window's ACTIVE surface. Measured on this machine with a two-pane
        # split and with two tabs:
        #
        #   bell in the active pane/tab    -> title marked, badge shows it
        #   bell in a background pane/tab  -> title NOT marked, badge blind
        #   bells in both panes            -> still one glyph, undercounted
        #
        # That is ghostty's `title` bell-feature working as designed: the window
        # title belongs to the active surface, so a background surface ringing
        # cannot change it.
        #
        # The gap is covered by the `.urgent` styling in the CSS below rather
        # than here. ghostty's `attention` bell-feature is independent of
        # `title`, and it DOES fire for background panes — verified: a bell in a
        # background pane emitted `urgent>>` on Hyprland's socket while the
        # title stayed unmarked. So the underline says "something here wants
        # you" in every case, and the bells add "how many windows" when they can.
        #
        # A per-pane count is not reachable: `hyprctl clients` exposes no urgent
        # field at all in 0.55.4, waybar's urgent handling is a single boolean
        # class, and neither ghostty nor Hyprland surfaces per-surface state to
        # an external process.
        window-rewrite = {
          "title<.*🔔.*>" = "󰂚";
        };
        # Empty, not the "?" default: without this every ordinary window would
        # add a glyph and the badge would just be a window count.
        window-rewrite-default = "";
        format-window-separator = "";
        # Always show 1-5 even when empty, so the bar doesn't reflow every time
        # a workspace empties out. 6-9 (bound in hyprland.nix) appear on demand.
        persistent-workspaces."*" = 5;
      };

      # Now playing. Native module (waybar links libplayerctl), so this is the
      # same MPRIS source the XF86Audio* binds in hyprland.nix drive — no helper
      # script. Hides itself entirely when nothing is playing, so the left edge
      # is just the clock most of the time.
      mpris = {
        format = "{player_icon} {dynamic}";
        format-paused = "{status_icon} <i>{dynamic}</i>";
        player-icons.default = "󰝚";
        status-icons.paused = "󰏤";
        dynamic-order = [
          "title"
          "artist"
        ];
        dynamic-len = 40;
        max-length = 45;
        on-click = "playerctl play-pause";
        on-scroll-up = "playerctl next";
        on-scroll-down = "playerctl previous";
      };

      idle_inhibitor = {
        format = "{icon}";
        # Coffee cup = caffeinated = staying awake; zzz = will fall asleep. The
        # module's own state names are the confusing part ("activated" means the
        # *inhibitor* is on, i.e. the screen does NOT sleep), so lead with the
        # metaphor in the icon and never make the tooltip rely on those words.
        format-icons = {
          activated = "󰅶"; # coffee
          deactivated = "󰒲"; # zzz
        };
        # Each tooltip says what is true NOW on the first line, then what the
        # click will do. Timings come from services.hypridle in hyprland.nix —
        # keep them in step if those change.
        tooltip-format-deactivated = "󰒲 Screen WILL sleep\nLocks after 5 min idle, suspends after 10.\n\nClick to keep it awake.";
        tooltip-format-activated = "󰅶 Screen is being kept AWAKE\nNo lock, no suspend, however long you idle.\n\nClick to let it sleep again.";
      };

      # us <-> sk indicator for the Alt+Shift toggle. `{short}` renders the
      # layout code (us/sk); map it with format-us/format-sk if you want
      # different text. If this ever tracks the wrong device (external keyboard),
      # pin it with `keyboard-name` from `hyprctl devices`.
      # Failed systemd units. On a declarative system a unit that dies after a
      # switch is otherwise completely silent — this repo's own vdirsyncer.service
      # sat failed for hours before anyone noticed.
      #
      # It does watch the USER manager, not just the system one: RequestSystemState
      # reads SystemState from BOTH proxies and only reports "ok" when both are
      # "running", which is what makes a failed --user unit visible here. Counting
      # is skipped entirely while the state is ok, so this is nearly free.
      #
      # hide-on-ok defaults to true; stated anyway because the whole point is that
      # it occupies no space on a healthy system.
      "systemd-failed-units" = {
        hide-on-ok = true;
        format = "󰀪 {nr_failed}";
        on-click = "ghostty -e ${lib.getExe failedUnitsScript}";
      };

      # Mic / screenshare in use. Renders GTK symbolic icons compiled into the
      # waybar binary as a GResource (resources/icons/waybar_icons.gresource.xml)
      # — not text glyphs, so there is no nerd-font codepoint to pick here, and
      # the colour comes from #privacy-item in the CSS below.
      #
      # `modules` is left at its default of screenshare + audio-in on purpose.
      # audio-out is the third available type but would light up for any music
      # playback, which is not a privacy event and would make the indicator noise.
      privacy = {
        icon-size = 14; # 20 by default, which overhangs a bar this height
        icon-spacing = 6;
      };

      # CPU package temperature.
      #
      # hwmon-path-abs, NOT the default thermal zone: on this machine
      # thermal_zone0 is acpitz and reports a flat, wrong ~82°C, while the real
      # sensor is k10temp (AMD). Addressed by the parent device path rather than
      # /sys/class/hwmon/hwmon4 because hwmonN numbering is not stable across
      # boots — the number moved would silently point this at the battery or the
      # NVMe drive. (This PCI address is the AMD SMU; it happens to be the exact
      # path used as the example in waybar-temperature(5).)
      #
      # 80/95 rather than something lower: this is an AMD mobile part that boosts
      # into the high 80s under a normal `nixos-rebuild` and is designed to, so
      # amber means "working hard" and red is near the ~95°C Tctl throttle point.
      # Anything stricter would sit amber during every build.
      temperature = {
        hwmon-path-abs = "/sys/devices/pci0000:00/0000:00:18.3/hwmon";
        input-filename = "temp1_input";
        warning-threshold = 80;
        critical-threshold = 95;
        format = "󰔏 {temperatureC}°C";
        tooltip-format = "CPU package {temperatureC}°C";
        interval = 5;
      };

      "custom/vpn" = {
        exec = lib.getExe vpnScript;
        return-type = "json";
        interval = 10;
      };

      # us <-> sk indicator for the Alt+Shift toggle, as an explicit uppercase
      # code rather than the lowercase xkb name.
      #
      # The `format-*` keys are matched on the xkb BRIEF, not the layout name —
      # language.cpp looks up `format-<short_description>`, and getLayout() fills
      # short_description from rxkb_layout_get_brief(). For these two that means
      # `format-en` (not format-us) and `format-sk`; verified against
      # xkeyboard_config's evdev.xml, where "English (US)" is name=us brief=en and
      # "Slovak" is name=sk brief=sk.
      #
      # `{}` positional, NOT `{short}`: the format-* branch formats `format` with
      # one positional argument, so a named placeholder there would not resolve.
      # An unmatched layout falls through to the generic branch and renders the
      # full name ("English (US)") instead — checked with `waybar -l debug`, it
      # degrades rather than throwing.
      "hyprland/language" = {
        format = "󰌌 {}";
        format-en = "US";
        format-sk = "SK";
      };

      backlight = {
        format = "{icon} {percent}%";
        format-icons = [
          "󰃞"
          "󰃟"
          "󰃠"
        ];
        # brightnessctl rather than waybar's built-in logind path, to match the
        # XF86MonBrightness binds exactly. brightnessctl is a system package
        # (modules/nixos/laptop.nix).
        on-scroll-up = "brightnessctl set 5%+";
        on-scroll-down = "brightnessctl set 5%-";
        # Click toggles the night light. Scroll already owns brightness, so click
        # was free, and "how warm is the screen" belongs with "how bright is the
        # screen" rather than in a module of its own.
        on-click = lib.getExe nightLightScript;
        # tooltip stays off: the tint IS the feedback, and a tooltip would have to
        # duplicate state the script already has to track in a file.
        tooltip = false;
      };

      # wireplumber, not pulseaudio: desktop.nix runs PipeWire with
      # services.pulseaudio disabled, so this reads the real session manager.
      wireplumber = {
        format = "{icon} {volume}%";
        format-muted = "󰝟 {volume}%";
        format-icons = [
          "󰕿"
          "󰖀"
          "󰕾"
        ];
        # Left-click mutes/unmutes, matching what the speaker icon looks like it
        # should do; pavucontrol moves to right-click. Same left=act,
        # right=manage split as the network module below.
        #
        # `on-click` is safe to set here even though `on-scroll-*` is not — only
        # the scroll handler has the early-return that bypasses the module's
        # volume clamping. Wireplumber implements no click handler of its own, so
        # there is no built-in behaviour to lose.
        on-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
        on-click-right = "pavucontrol";
        # Scrolling is handled by the module's OWN handler, deliberately: do NOT
        # add on-scroll-up/on-scroll-down here. Wireplumber::handleScroll starts
        # with `if (on-scroll-up || on-scroll-down) return AModule::handleScroll`
        # — setting either one opts the module out of its own clamping and just
        # shells out per scroll tick, which is exactly how volume escaped past
        # 100% when scrolling on the label. The native path clamps to max-volume
        # and calls the WirePlumber API directly, with no process per event.
        scroll-step = 5; # match the 5% XF86Audio* keyboard step
        max-volume = 100; # the built-in default too, but state it explicitly
        tooltip-format = "{node_name}";
      };

      bluetooth = {
        format = "󰂯";
        format-off = "󰂲";
        format-disabled = "󰂲";
        format-connected = "󰂱 {num_connections}";
        tooltip-format = "{controller_alias}";
        tooltip-format-connected = "{device_enumerate}";
        tooltip-format-enumerate-connected = "{device_alias}";
        on-click = "blueman-manager";
      };

      # The ONLY network indicator — nm-applet's tray icon used to sit next to
      # this one saying the same thing, and is gone from exec-once now.
      network = {
        format-wifi = "󰖩 {essid}";
        format-ethernet = "󰈀 {ifname}";
        format-disconnected = "󰖪 offline";
        tooltip-format-wifi = "{essid} ({signalStrength}%)\n{ipaddr}";
        tooltip-format-ethernet = "{ifname}\n{ipaddr}";
        tooltip-format-disconnected = "Disconnected";
        # Left: manage saved connections. Right: nmtui, which is the one that can
        # actually scan for and join a new network now that nm-applet is gone —
        # nm-connection-editor only edits connections, it cannot prompt for a
        # wifi password. `ghostty -e` matches how fuzzel launches terminal apps.
        on-click = "nm-connection-editor";
        on-click-right = "ghostty -e nmtui";
        max-length = 24;
      };

      # `bat` is deliberately unset: hardware-configuration.nix is still a
      # placeholder, so the BAT0/BAT1 name isn't known here. Waybar autodetects.
      battery = {
        states = {
          warning = 30;
          critical = 15;
        };
        format = "{icon} {capacity}%";
        format-charging = "󰂄 {capacity}%";
        format-plugged = "󰚥 {capacity}%";
        format-icons = [
          "󰁺"
          "󰁻"
          "󰁼"
          "󰁽"
          "󰁾"
          "󰁿"
          "󰂀"
          "󰂁"
          "󰂂"
          "󰁹"
        ];
        tooltip-format = "{timeTo} ({power} W)";
      };

      # First module in modules-left, so this is the top-left corner of the
      # screen: time, zone, date, then custom/meetings — one cluster, read left
      # to right, both halves opening the same window on click.
      #
      # Date is %Y/%m/%d rather than %x on purpose: %x follows LC_TIME, which
      # core.nix now sets to en_GB for Monday-first weeks, and would render this
      # as 10/09/26 — little-endian and ambiguous next to a 24h time.
      # Big-endian sorts, and never has to be guessed at.
      "custom/clock" = {
        exec = lib.getExe clockScript;
        return-type = "json";
        # No `interval`: clockScript is a subscription-style module that prints a
        # line per minute on the boundary. restart-interval is the safety net for
        # the loop ever dying — without it waybar would leave the module blank
        # for the rest of the session.
        restart-interval = 5;
        # Opens the week view (modules/home/calendar.nix). Store path rather
        # than a bare `gnome-calendar`: waybar runs as a systemd user unit here,
        # so a PATH miss would fail silently on click with nothing in the log
        # worth reading.
        on-click = lib.getExe pkgs.gnome-calendar;
      };

      # CPU + RAM at a glance, top processes on hover, btop on click.
      "custom/perf" = {
        exec = lib.getExe perfScript;
        # The script emits {text, tooltip, class}; without this waybar would
        # print the raw JSON as the label.
        return-type = "json";
        interval = 5;
        on-click = "ghostty -e btop";
      };

      # Notification indicator + entry point to swaync's control centre
      # (modules/home/notifications.nix). Sits at the right edge of the LEFT
      # group so it is adjacent to the panel, which opens on the left.
      #
      # `swaync-client -swb` is a long-running subscription, not a polled
      # command: it prints a fresh JSON line on every notification add/close.
      # So there is deliberately no `interval` — adding one would make waybar
      # re-exec it on a timer and lose the subscription. Store path rather than
      # a bare name because waybar runs as a systemd user unit, where a PATH
      # miss fails silently.
      "custom/notification" = {
        exec = "${lib.getExe' pkgs.swaynotificationcenter "swaync-client"} -swb";
        return-type = "json";
        # swaync emits its own class per state; these are the glyphs for them.
        # The dot variants mark "unread" so a glance distinguishes an empty
        # tray from a waiting one without reading a count.
        format = "{icon}";
        format-icons = {
          notification = "󰂚<span foreground='#8ba4b0'><sup>󰺕</sup></span>";
          none = "󰂜";
          dnd-notification = "󰂛<span foreground='#8ba4b0'><sup>󰺕</sup></span>";
          dnd-none = "󰂛";
          inhibited-notification = "󰂚<span foreground='#8ba4b0'><sup>󰺕</sup></span>";
          inhibited-none = "󰂜";
          dnd-inhibited-notification = "󰂛<span foreground='#8ba4b0'><sup>󰺕</sup></span>";
          dnd-inhibited-none = "󰂛";
        };
        # The glyphs above are pango markup, so waybar must not escape them.
        escape = false;
        tooltip = true;
        on-click = "${lib.getExe' pkgs.swaynotificationcenter "swaync-client"} -t -sw";
        on-click-right = "${lib.getExe' pkgs.swaynotificationcenter "swaync-client"} -d -sw";
      };

      "custom/power" = {
        format = "󰐥";
        tooltip = false;
        on-click = "wlogout";
      };

      tray = {
        icon-size = 16;
        spacing = 10;
      };
    }
    # One counter per calendar group, generated so that adding a feed to
    # `my.calendars` is the only edit needed — a new group appears on the bar on
    # its own, and a group that loses its last counted calendar disappears.
    // lib.listToAttrs (
      map (
        grp:
        lib.nameValuePair "custom/meetings-${grp.group}" {
          exec = lib.getExe (meetingsScriptFor grp);
          return-type = "json";
          # 60s, not the 5s custom/perf uses: the count answers "what's left
          # today", which changes when a meeting ENDS, not when the feed does
          # (vdirsyncer only pulls every 30 min anyway). One khal run measures
          # ~0.25s, dominated by Python start-up, so a minute tick is free and
          # keeps these in step with the clock they sit beside.
          interval = 60;
          # Same target as the clock, so clicking anywhere in the left cluster
          # gets you the week view rather than making you aim.
          on-click = lib.getExe pkgs.gnome-calendar;
        }
      ) meetingGroups
    );

    # Stylix owns the base styling (background, font, tooltip colors, and the
    # #workspaces focused/urgent underline) and declares `style` as a
    # types.lines option across three separate blocks — so this MERGES rather
    # than conflicting. That is the opposite of fuzzel's [colors] section (see
    # hyprland.nix), which is a hard module conflict if you touch it.
    #
    # mkAfter so these land last and win the cascade. Everything here either
    # sets a property Stylix doesn't, or targets a selector it never emits —
    # the `.modules-left #workspaces button.active` underline is left alone.
    style = lib.mkAfter ''
      /* Stylix sets the background; this just separates the bar from the
         window below it, which matters at gaps_out = 10. */
      window#waybar {
        border-bottom: 2px solid @base02;
      }

      /* Vertical breathing room. Stylix only ever sets horizontal padding
         (`padding: 0 5px`), and only on the modules it knows by name. */
      .modules-left, .modules-center, .modules-right {
        padding: 2px 0;
      }

      #workspaces button {
        padding: 0 8px;
        margin: 0;
        border-radius: 0;
        background: transparent;
        color: @base04;
      }
      /* GTK's default button hover adds a shadow that reads as a smear here. */
      #workspaces button:hover {
        background: @base01;
        box-shadow: none;
        text-shadow: none;
      }
      #workspaces button.active {
        color: @base05;
      }
      #workspaces button.empty {
        color: @base03;
      }
      /* A workspace with something waiting.

         This is NOT decoration for the badge — it is the half that catches what
         the badge cannot see. window-rewrite matches the window title, which
         only tracks a ghostty window's ACTIVE surface, so a bell in a
         background pane or tab never marks it. ghostty's `attention` bell
         feature is separate and fires regardless, which reaches waybar as
         Hyprland's `urgent` event and lands here. Verified: a background-pane
         bell produced this underline with no bell glyph beside the number.

         So: underline = "something on this workspace wants you", bells = "how
         many windows, where the ringing surface was the visible one".

         Selector deliberately mirrors Stylix's own `.modules-center #workspaces
         button.urgent` rather than the shorter `#workspaces button.urgent`:
         Stylix's is more specific, so the short form loses even though this
         block is mkAfter — specificity beats source order.

         Stylix fills the whole button with base08 (red) and inverts the text.
         That reads as "something is broken" for what is only a terminal bell,
         and at three lit workspaces the bar became a red slab. Amber underline
         instead, matching the .active underline's shape. */
      .modules-center #workspaces button.urgent {
        background-color: transparent;
        border-bottom: 3px solid @base0A;
        color: @base0A;
      }

      /* Dim now-playing so it recedes behind the clock and the status cluster. */
      #mpris {
        color: @base04;
        padding: 0 5px;
      }

      /* Remaining modules Stylix has no padding rule for (#mpris gets its own
         above). It DOES already cover #idle_inhibitor, #language, #bluetooth,
         #clock, #backlight, #network, #battery and #wireplumber — don't re-add
         those, they'd just be redundant lines to keep in sync.

         #custom-clock is here rather than free: Stylix's rule is on #clock, and
         swapping the built-in module for a custom one renamed the selector. */
      #tray,
      #custom-perf,
      #custom-clock,
      #custom-notification,
      #custom-vpn,
      #privacy,
      #systemd-failed-units,
      #custom-power {
        padding: 0 5px;
      }

      /* Red, like #privacy-item: it is only ever visible when something is
         actually broken, so there is no benign tier to colour. */
      #systemd-failed-units {
        color: @base08;
      }

      /* Privacy: red whenever it is visible. No green/amber tier here because
         there is no benign state to show — the module hides itself entirely when
         nothing is capturing, so "present" already means "in use".
         #privacy-item is the per-type box (set_name in privacy_item.cpp); the
         icons are -symbolic, so GTK recolours them from this `color`. */
      #privacy-item {
        color: @base08;
      }

      /* Same green/amber/red scale as #custom-perf next to it, but driven by CSS
         classes rather than inline spans: temperature is a single metric, so the
         module-wide class that Temperature::update() sets from
         warning-threshold/critical-threshold expresses it exactly. */
      #temperature {
        color: @base0B;
      }
      #temperature.warning {
        color: @base0A;
      }
      #temperature.critical {
        color: @base08;
      }

      /* Green: visible at all only while a tunnel is up, so it always means
         "protected". */
      #custom-vpn {
        color: @base0B;
      }

      /* Per-group counters, so these selectors are generated: one counter per
         `my.calendarGroups` entry that has counted calendars in it.

         Nothing left today is the normal state, so it recedes like #mpris does
         rather than sitting there at full contrast. Amber for a feed that has
         stopped updating, red only for "khal could not read this at all" —
         both are cases where the number on the bar cannot be trusted, which is
         the whole reason the script computes a class. */
      ${meetingCss}

      /* Dimmed to match #mpris beside it, so an empty tray recedes. The
         unread state is carried by the superscript dot in the glyph itself
         (see custom/notification above), not by a colour change here — a
         recolour would fight Stylix's own module colours. */
      #custom-notification {
        color: @base04;
      }
      #custom-notification:hover {
        color: @base05;
      }

      /* No colour rules for #custom-perf.warning/.critical on purpose: the
         module colours CPU and RAM separately via inline <span color>, and an
         inline span beats a CSS rule, so anything here would be dead code that
         looks live. The classes are still emitted if you ever want a background
         or border keyed to the module's overall state. */

      #custom-power {
        color: @base08;
        padding-right: 10px;
      }

      /* State colors — the whole point of having a bar you can glance at. */
      #battery.warning { color: @base0A; }
      #battery.critical { color: @base08; }
      #battery.charging { color: @base0B; }
      #network.disconnected { color: @base08; }
      #wireplumber.muted { color: @base03; }
      #idle_inhibitor.activated { color: @base0A; }
    '';
  };

  # A reload is not enough for this bar. HM wires X-Reload-Triggers on the
  # generated config/style plus ExecReload=kill -SIGUSR2, so a switch that only
  # changes the config reloads waybar in place — and waybar's SIGUSR2 handler
  # loads the new config WITHOUT re-arming the interval timers of custom
  # modules. Observed exactly once and then obvious: the clock rendered the
  # minute it reloaded and froze there, while `pgrep -P <waybar>` showed no
  # waybar-clock or waybar-perf children at all.
  #
  # So turn the reload into a real restart. --no-block is load-bearing: without
  # it systemd would sit inside the reload job waiting for a restart of the same
  # unit to complete, which cannot happen until the reload finishes.
  systemd.user.services.waybar.Service.ExecReload =
    lib.mkForce "${pkgs.systemd}/bin/systemctl --user restart --no-block waybar.service";
}
