# Waybar: the Hyprland status bar. Split out of hyprland.nix because the bar's
# module/style config is bigger than the compositor's.
#
# Why this file exists at all: `programs.waybar.enable = true` alone writes NO
# config, so waybar falls back to the upstream default (/etc/xdg/waybar/config),
# which is written for Sway. Under Hyprland every `sway/*` module in it silently
# does nothing — meaning no workspaces, no window title, and no keyboard-layout
# indicator (the last one matters here: kb_options = grp:alt_shift_toggle
# switches us <-> sk with zero visual feedback). The default also carries modules
# that can't work on this machine: mpd, custom/media (points at a mediaplayer.py
# that doesn't exist), battery#bat2, and power-profiles-daemon — which laptop.nix
# explicitly disables in favour of TLP.
{ lib, ... }:
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

      modules-left = [ "hyprland/workspaces" ];
      modules-center = [ "hyprland/window" ];
      modules-right = [
        "tray"
        "idle_inhibitor"
        "hyprland/language"
        "backlight"
        "wireplumber"
        "bluetooth"
        "network"
        "battery"
        "clock"
        "custom/power"
      ];

      "hyprland/workspaces" = {
        format = "{name}";
        on-click = "activate";
        # Always show 1-5 even when empty, so the bar doesn't reflow every time
        # a workspace empties out. 6-9 (bound in hyprland.nix) appear on demand.
        persistent-workspaces."*" = 5;
      };

      "hyprland/window" = {
        format = "{title}";
        max-length = 70;
        separate-outputs = true;
        # Browsers append their own name to every title, which eats the width
        # that the actual page title needs. Both of ours, stripped:
        rewrite = {
          "(.*) — LibreWolf" = "$1";
          "(.*) - Chromium" = "$1";
        };
      };

      idle_inhibitor = {
        format = "{icon}";
        format-icons = {
          activated = "󰅶";
          deactivated = "󰛊";
        };
        # hypridle locks at 5 min / suspends at 10 (see hyprland.nix). Click this
        # before a video call or a long build to hold both off.
        tooltip-format-activated = "Idle inhibited";
        tooltip-format-deactivated = "Idle timer active";
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
        on-click = "pavucontrol";
        on-scroll-up = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+";
        on-scroll-down = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
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

      network = {
        format-wifi = "󰖩 {essid}";
        format-ethernet = "󰈀";
        format-disconnected = "󰖪";
        tooltip-format-wifi = "{essid} ({signalStrength}%)\n{ipaddr}";
        tooltip-format-ethernet = "{ifname}\n{ipaddr}";
        tooltip-format-disconnected = "Disconnected";
        on-click = "nm-connection-editor";
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

      clock = {
        format = "{:%H:%M}";
        # Click to expand to the full date, click again to collapse.
        format-alt = "{:%a %d %b  %H:%M}";
        tooltip-format = "<tt><small>{calendar}</small></tt>";
        calendar = {
          mode = "month";
          weeks-pos = "right";
          format.today = "<b><u>{}</u></b>";
        };
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

      /* Dim the title so it recedes behind the workspace/status indicators. */
      #window {
        color: @base04;
      }

      /* The two modules Stylix has no padding rule for. It does cover
         #idle_inhibitor, #language and #bluetooth already — don't re-add those,
         they'd just be redundant lines to keep in sync. */
      #tray,
      #custom-power {
        padding: 0 5px;
      }

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
