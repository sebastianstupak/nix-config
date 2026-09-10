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
      "$mod" = "SUPER";
      "$terminal" = "ghostty";
      "$menu" = "wofi --show drun";

      monitor = ",preferred,auto,1";

      exec-once = [
        "waybar"
        "mako"
        "hypridle"
        "nm-applet --indicator"
        "blueman-applet"
        "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
      ];

      input = {
        kb_layout = "us,sk";
        kb_options = "grp:win_space_toggle"; # Super+Space cycles US <-> SK
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
        "$mod, Return, exec, $terminal"
        "$mod, Q, killactive"
        "$mod, E, exec, nautilus"
        "$mod, R, exec, $menu"
        "$mod, V, togglefloating"
        "$mod, F, fullscreen"
        "$mod, L, exec, hyprlock"

        # focus movement
        "$mod, left, movefocus, l"
        "$mod, right, movefocus, r"
        "$mod, up, movefocus, u"
        "$mod, down, movefocus, d"

        # workspaces
        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"

        # region screenshot to clipboard
        ", Print, exec, grim -g \"$(slurp)\" - | wl-copy"
      ];

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
    wl-clipboard # wl-copy / wl-paste
    networkmanagerapplet # nm-applet
    nautilus # file manager
    polkit_gnome # authentication agent
  ];

  # Hint Electron/Chromium apps to run natively on Wayland.
  home.sessionVariables.NIXOS_OZONE_WL = "1";
}
