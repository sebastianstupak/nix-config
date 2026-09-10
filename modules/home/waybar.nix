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

  # Feeds custom/meetings: how many of today's meetings are still ahead. Reads
  # the local mirror of the Proton feed — modules/home/calendar.nix owns how it
  # gets there, and both paths below are derived from the same options it
  # configures vdirsyncer with, so the bar cannot drift from the syncer.
  #
  # khal rather than reading the .ics files here: a vdir holds raw VEVENTs, so
  # anything hand-rolled would have to expand RRULEs and resolve VTIMEZONEs
  # itself — a daily standup would either vanish or show up once, in 2019. khal
  # does both already, and `--json` (0.14+) hands back fields instead of the
  # human table that older waybar recipes scrape with awk.
  meetingsScript = pkgs.writeShellApplication {
    name = "waybar-meetings";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.khal
      pkgs.jq
    ];
    text = ''
      status=${lib.escapeShellArg "${config.accounts.calendar.basePath}/.vdirsyncer-status/proton.items"}

      # Freshness first, because a frozen count is worse than no count: Proton's
      # share links are documented to stop feeding third-party clients after a
      # while, and the only symptom is a number that quietly stops moving.
      # vdirsyncer rewrites this file on every successful sync, including no-op
      # ones, so its mtime is the real "last synced".
      stale=no
      if [ -f "$status" ]; then
        mins=$(( ( $(date +%s) - $(stat -c %Y "$status") ) / 60 ))
        synced="$mins min ago"
        [ "$mins" -gt 720 ] && stale=yes
      else
        synced="never"
        stale=yes
      fi

      # `today 1d` means today ONLY — the range argument is a length, not an end
      # date. Asking for fields rather than a format string so the filter below
      # can read them; khal accepts --json repeatedly.
      if ! events=$(khal list --json title --json start-time --json end-time \
                              --json end today 1d 2>&1); then
        jq -cn --arg err "$events" \
          '{text: "󰃭 ?", tooltip: ("khal could not read the calendar:\n" + $err),
            class: "error"}'
        exit 0
      fi

      # Filtering on `end`, not `start`: a meeting you are sitting in is still
      # one of today's meetings, and --notstarted is no help — it filters against
      # the START of the range (00:00 today), so it keeps everything. `end`
      # carries the date as well as the time, which also gets the 23:45 event
      # ending at 00:00 right; comparing bare clock times would drop it.
      #
      # All-day entries are excluded by the empty start-time: they are not
      # meetings, and counting them would put a permanent +1 on the bar.
      jq -cn --argjson evs "$events" --arg now "$(date '+%Y-%m-%d %H:%M')" \
             --arg synced "$synced" --arg stale "$stale" '
        def esc: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
        [ $evs[] | select(."start-time" != "" and .end > $now) ] as $left
        | ($left | length) as $n
        | {
            text: "󰃭 \($n)",
            tooltip: (
              (if $n == 0 then "<b>Nothing left today</b>"
               else "<b>\($n) left today</b>\n"
                    + ([ $left[] | "  \(."start-time")–\(."end-time")  \(.title | esc)" ]
                       | join("\n"))
               end)
              + "\n<i>Synced \($synced)"
              + (if $stale == "yes" then " — check systemctl --user status vdirsyncer" else "" end)
              + "</i>"
            ),
            class: (if $stale == "yes" then "stale" elif $n == 0 then "none" else "ok" end),
          }'
    '';
  };
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
        "clock"
        "custom/meetings"
        "custom/notification"
        "mpris"
      ];
      modules-center = [ "hyprland/workspaces" ];
      modules-right = [
        "custom/perf"
        "tray"
        "idle_inhibitor"
        "hyprland/language"
        "backlight"
        "wireplumber"
        "bluetooth"
        "network"
        "battery"
        "custom/power"
      ];

      "hyprland/workspaces" = {
        format = "{name}";
        on-click = "activate";
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
      "hyprland/language" = {
        format = "󰌌 {short}";
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
      # screen: time, then the date, then custom/meetings — one cluster, read
      # left to right, all three opening the same window on click.
      #
      # Date spelled out as %Y/%m/%d rather than %x on purpose: %x follows
      # LC_TIME, which core.nix now sets to en_GB for Monday-first weeks, and
      # would render this as 10/09/26 — little-endian and ambiguous next to a
      # 24h time. Big-endian sorts, and never has to be guessed at.
      clock = {
        format = "{:%H:%M  %Y/%m/%d}";
        # Opens the week view (modules/home/calendar.nix). Store path rather
        # than a bare `gnome-calendar`: waybar runs as a systemd user unit here,
        # so a PATH miss would fail silently on click with nothing in the log
        # worth reading.
        #
        # This is also why there is no `format-alt` any more — waybar wires
        # format-alt toggling to on-click, so the two can't coexist, and with
        # the date permanently on the bar the alt format had nothing left to
        # reveal.
        on-click = lib.getExe pkgs.gnome-calendar;
        tooltip-format = "<tt><small>{calendar}</small></tt>";
        calendar = {
          mode = "month";
          weeks-pos = "right";
          format.today = "<b><u>{}</u></b>";
        };
      };

      # Today's remaining meetings, next to the date it belongs with.
      "custom/meetings" = {
        exec = lib.getExe meetingsScript;
        return-type = "json";
        # 60s, not the 5s custom/perf uses: the count answers "what's left
        # today", which changes when a meeting ENDS, not when the feed does
        # (vdirsyncer only pulls every 30 min anyway). One khal run measures
        # ~0.25s, dominated by Python start-up, so a minute tick is free and
        # keeps this in step with the clock it sits beside.
        interval = 60;
        # Same target as the clock, so clicking anywhere in the left cluster
        # gets you the week view rather than making you aim.
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
    };

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

      /* Dim now-playing so it recedes behind the clock and the status cluster. */
      #mpris {
        color: @base04;
        padding: 0 5px;
      }

      /* Remaining modules Stylix has no padding rule for (#mpris gets its own
         above). It DOES already cover #idle_inhibitor, #language, #bluetooth,
         #clock, #backlight, #network, #battery and #wireplumber — don't re-add
         those, they'd just be redundant lines to keep in sync. */
      #tray,
      #custom-perf,
      #custom-meetings,
      #custom-notification,
      #custom-power {
        padding: 0 5px;
      }

      /* Nothing left today is the normal state, so it recedes like #mpris does
         rather than sitting there at full contrast. Amber for a feed that has
         stopped updating, red only for "khal could not read this at all" —
         both are cases where the number on the bar cannot be trusted, which is
         the whole reason the script computes a class. */
      #custom-meetings.none {
        color: @base04;
      }
      #custom-meetings.stale {
        color: @base0A;
      }
      #custom-meetings.error {
        color: @base08;
      }

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
}
