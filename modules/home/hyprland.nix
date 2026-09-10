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

    settings = {
      # NOTE: this Hyprland build uses a Lua-generated config (home-manager writes
      # hyprland.lua). hyprlang "$var" keys become invalid Lua (`hl.$mod(...)`), so
      # we do NOT declare $mod/$terminal/$menu — values are inlined below instead.
      monitor = ",preferred,auto,1";

      exec-once = [
        "waybar"
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

      bind = [
        "SUPER, Return, exec, ghostty"
        "SUPER, Q, killactive"
        "SUPER, E, exec, nautilus"
        "SUPER, R, exec, wofi --show drun"
        "SUPER, V, togglefloating"
        "SUPER, F, fullscreen"
        "SUPER, L, exec, hyprlock"
        "SUPER SHIFT, X, exec, wlogout" # power menu
        "SUPER, C, exec, cliphist list | wofi --dmenu | cliphist decode | wl-copy" # clipboard history

        # focus movement
        "SUPER, left, movefocus, l"
        "SUPER, right, movefocus, r"
        "SUPER, up, movefocus, u"
        "SUPER, down, movefocus, d"

        # workspaces
        "SUPER, 1, workspace, 1"
        "SUPER, 2, workspace, 2"
        "SUPER, 3, workspace, 3"
        "SUPER, 4, workspace, 4"
        "SUPER SHIFT, 1, movetoworkspace, 1"
        "SUPER SHIFT, 2, movetoworkspace, 2"
        "SUPER SHIFT, 3, movetoworkspace, 3"
        "SUPER SHIFT, 4, movetoworkspace, 4"

        # region screenshot to clipboard
        ", Print, exec, grim -g \"$(slurp)\" - | wl-copy"
        # Windows-style snipping tool: region screenshot -> annotate (swappy)
        "SUPER SHIFT, S, exec, grim -g \"$(slurp)\" - | swappy -f -"

        # media keys (Spotify, browsers, ... via MPRIS/playerctl)
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPrev, exec, playerctl previous"
      ];

      bindm = [
        "SUPER, mouse:272, movewindow"
        "SUPER, mouse:273, resizewindow"
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

  # Bar, notifications, launcher, screen lock, idle daemon.
  programs.waybar.enable = true;
  services.mako.enable = true;
  programs.wofi.enable = true;
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
