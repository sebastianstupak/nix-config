# Hyprland Wayland desktop: compositor config, bar, launcher, notifications,
# lock/idle, and supporting utilities. System-level Hyprland (the session) is
# enabled in modules/nixos/desktop.nix; here we own the per-user config.
{ pkgs, ... }:
{
  wayland.windowManager.hyprland = {
    enable = true;
    # Use the Hyprland from the system (programs.hyprland.enable) to avoid
    # installing/most-importantly version-mismatching two copies.
    package = null;
    portalPackage = null;

    # On Hyprland 0.55 the HM module defaults to a Lua config (hyprland.lua), whose
    # serialization mangles bind strings (`hl.bind("SUPER, Return, ...")` is not a
    # valid call). Force the classic hyprlang format (hyprland.conf) — it renders
    # these bind/exec-once/variable settings correctly.
    configType = "hyprlang";

    settings = {
      "$mod" = "SUPER";
      "$terminal" = "ghostty";
      "$menu" = "fuzzel";

      monitor = ",preferred,auto,1";

      # No waybar here: it runs as a systemd user unit (modules/home/waybar.nix),
      # started by graphical-session.target. Launching it here too would give you
      # two bars.
      exec-once = [
        "mako"
        "hypridle"
        "nm-applet --indicator"
        "blueman-applet"
        "wl-paste --watch cliphist store" # clipboard history daemon
        "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
      ];

      input = {
        kb_layout = "us,sk";
        kb_options = "grp:alt_shift_toggle"; # Alt+Shift cycles US <-> SK (Windows-style)
        follow_mouse = 1;
        touchpad.natural_scroll = true;
      };

      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
        layout = "dwindle";
      };

      decoration.rounding = 6;

      # Hyprland's built-in defaults are cinematic — ~480ms for `windows` and
      # ~540ms for `border`, which makes focus changes feel laggy even though
      # focus itself is instant. Speeds are in deciseconds (1 unit = 100ms);
      # roughly halved here. `windows`/`border`/`fade`/`layers` are parent nodes,
      # so their children (windowsIn, fadeOut, layersIn, ...) inherit these
      # unless separately overridden.
      # To retune without a rebuild: hyprctl keyword animation "windows,1,1.4,snap"
      animations = {
        enabled = true;
        bezier = [
          "snap, 0.2, 1, 0.2, 1" # hard ease-out: moves immediately, settles fast
          "linear, 0, 0, 1, 1"
        ];
        animation = [
          "windows, 1, 2.2, snap, popin 92%"
          "windowsOut, 1, 1.6, snap, popin 92%"
          "border, 1, 2, linear"
          "fade, 1, 1.6, snap"
          "layers, 1, 1.8, snap, popin 95%"
          "workspaces, 1, 1.8, snap, slidefade 15%"
        ];
      };

      bind = [
        "$mod, Return, exec, $terminal"
        "$mod, Q, killactive"
        "$mod, E, exec, nautilus"
        # Toggle, not just launch: fuzzel has no single-instance lock, so
        # pressing $mod+R twice would stack a second launcher on the first.
        # pkill exits 1 when nothing matched (-> open it), 0 when it killed one
        # (-> stays closed). Hyprland runs exec through sh -c, so `||` works.
        # Substring match rather than `pkill -x`: fuzzel happens to be an
        # unwrapped ELF today (comm is exactly `fuzzel`, so -x would work), but
        # wofi here was `.wofi-wrapped` and an exact match found NOTHING —
        # the toggle silently degraded back to stacking. Not worth re-learning
        # if this ever gains a wrapper. Keep the pattern short: procps matches
        # against comm, which is capped at 15 chars.
        "$mod, R, exec, pkill fuzzel || $menu"
        "$mod, V, togglefloating"
        # Two fullscreen modes: 0 (default) is true fullscreen — covers the bar
        # and gaps. 1 is "maximize": fills the workspace but keeps waybar and
        # the gaps, which is what you usually want for a wide editor/browser.
        "$mod, F, fullscreen, 0"
        "$mod SHIFT, F, fullscreen, 1"
        "$mod, L, exec, hyprlock"
        "$mod SHIFT, X, exec, wlogout" # power menu
        "$mod, C, exec, cliphist list | fuzzel --dmenu | cliphist decode | wl-copy" # clipboard history

        # Waybar signals: USR1 hides/shows the bar (handy for a full-width
        # editor without leaving true fullscreen). USR2 re-reads config + CSS —
        # not needed after a rebuild (the unit reloads itself, see waybar.nix),
        # but it fixes the bar re-laying-out wrong after a monitor hotplug.
        # Plain `pkill waybar`, NOT `pkill -x`: waybar is a wrapped binary, so
        # its comm is `.waybar-wrapped` — an exact match finds nothing. Same
        # trap as fuzzel above; it happens to fit in comm's 15-char cap exactly.
        "$mod, B, exec, pkill -SIGUSR1 waybar"
        "$mod SHIFT, B, exec, pkill -SIGUSR2 waybar"

        # focus movement
        "$mod, left, movefocus, l"
        "$mod, right, movefocus, r"
        "$mod, up, movefocus, u"
        "$mod, down, movefocus, d"

        # region screenshot to clipboard
        ", Print, exec, grim -g \"$(slurp)\" - | wl-copy"
        # Windows-style snipping tool: region screenshot -> annotate (swappy)
        "$mod SHIFT, S, exec, grim -g \"$(slurp)\" - | swappy -f -"

        # media keys (Spotify, browsers, ... via MPRIS/playerctl)
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPrev, exec, playerctl previous"
      ]
      # Workspaces 1-9: $mod+N focuses it, $mod+SHIFT+N sends the focused window
      # there. Generated rather than written out 18 times — the two lines below
      # are the whole spec. `movetoworkspace` follows the window to the new
      # workspace; swap in `movetoworkspacesilent` to stay put instead.
      ++ builtins.concatMap (n: [
        "$mod, ${n}, workspace, ${n}"
        "$mod SHIFT, ${n}, movetoworkspace, ${n}"
      ]) (builtins.genList (i: toString (i + 1)) 9);

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];

      # repeatable audio / brightness keys
      bindel = [
        ", XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
        ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ", XF86MonBrightnessUp, exec, brightnessctl set 5%+"
        ", XF86MonBrightnessDown, exec, brightnessctl set 5%-"
      ];
    };
  };

  # Notifications, launcher, screen lock, idle daemon. The bar lives in
  # modules/home/waybar.nix.
  services.mako.enable = true;
  # Launcher. fuzzel over wofi: Wayland-native rather than GTK3, renders app
  # icons properly, and has a far richer Stylix target (11 color roles vs
  # wofi's 4) so it actually inherits the scheme instead of looking unstyled.
  # Stylix owns `main.font`, `main.icon-theme` and the whole [colors] section —
  # do NOT set those here. Stylix's mkTarget uses mkIf/mkMerge, not mkDefault,
  # so redefining them is a module-system conflict, not an override.
  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        # Compact geometry: `width` is in characters, the pads in pixels.
        # Renders ~416x392 rather than fuzzel's roomier defaults (width 30 but
        # 40px horizontal pad, 15 lines). wofi's stylix target set none of this,
        # which is why it rendered edge-to-edge.
        width = 32;
        lines = 8;
        horizontal-pad = 14;
        vertical-pad = 10;
        inner-pad = 8;
        line-height = 20;
        icons-enabled = true;
        # Match on more than the app name — `gvim` finds "GVim", but this also
        # lets "browser" find LibreWolf via its generic name/keywords.
        fields = "name,generic,keywords";
        # Empty (quoted, so it is an explicit empty value rather than "unset",
        # which would fall back to fuzzel's default "> "). Not `hide-prompt`:
        # that removes the whole input line, taking the placeholder and the
        # echo of what you type with it.
        prompt = ''""'';
        placeholder = "Search";
        # Needed by non-dmenu modes that launch terminal apps.
        terminal = "ghostty -e";
        # Above fullscreen windows, so $mod+R works over a maximized app.
        layer = "overlay";
        # Keyboard focus is left at fuzzel's default (exclusive). Dismissing by
        # clicking outside is not achievable: fuzzel is layer-shell only, and a
        # click outside a layer surface is swallowed by it — Hyprland does not
        # even change activewindow, so nothing can react to it either. Don't
        # reach for keyboard-focus=on-demand or input.follow_mouse to fix this;
        # both were tried and only trade the bug for a worse one (the launcher
        # closing on mere pointer movement). Escape, or $mod+R again, dismisses.
      };
      # Rounded to match decoration.rounding; layer surfaces don't inherit it.
      border = {
        radius = 10;
        width = 2;
      };
    };
  };
  programs.hyprlock.enable = true;
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
      };
      listener = [
        {
          timeout = 300; # lock after 5 min idle
          on-timeout = "hyprlock";
        }
        {
          timeout = 600; # suspend after 10 min idle
          on-timeout = "systemctl suspend";
        }
      ];
    };
  };

  # Utilities referenced by the binds / exec-once above.
  home.packages = with pkgs; [
    grim # screenshot
    slurp # region selector
    swappy # screenshot annotation (snipping tool)
    wl-clipboard # wl-copy / wl-paste
    cliphist # clipboard history
    wlogout # power menu
    pavucontrol # audio device / volume GUI
    networkmanagerapplet # nm-applet
    nautilus # file manager
    polkit_gnome # authentication agent
  ];

  # Hint Electron/Chromium apps to run natively on Wayland.
  home.sessionVariables.NIXOS_OZONE_WL = "1";
}
