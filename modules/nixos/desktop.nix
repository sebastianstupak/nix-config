# Graphical session: Hyprland (Wayland) + login manager, portals, audio, fonts.
# The per-user Hyprland/waybar/etc. config lives in home/ (modules/home/hyprland.nix).
{ pkgs, ... }:
{
  # Hyprland compositor. Provides the Wayland session and pulls in the
  # hyprland xdg-desktop-portal automatically.
  programs.hyprland = {
    enable = true;

    # Launch through UWSM rather than exec'ing the Hyprland binary directly.
    # UWSM puts the compositor inside a real systemd user session and starts
    # graphical-session.target / wayland-session@Hyprland.target itself. Without
    # it the session is stitched together by hand — the home-manager module has
    # to exec-once a dbus-update-activation-environment and manually start
    # hyprland-session.target — which leaves user units depending on that target
    # (waybar here) starting on a best-effort basis and never stopping cleanly
    # on logout. NixOS documents this as recommended for most users.
    withUWSM = true;
  };

  # GPU/OpenGL stack — needed for Ghostty's desktop-launch GL path and general
  # Wayland acceleration.
  hardware.graphics.enable = true;

  # Login manager: greetd + tuigreet, offering the installed Wayland sessions.
  #
  # `--sessions` rather than `--cmd Hyprland`: with UWSM the session has to be
  # started via its desktop entry (hyprland-uwsm.desktop) so UWSM can set up the
  # systemd units — exec'ing the bare binary silently bypasses all of that.
  # Listing the directory also keeps the plain hyprland.desktop entry selectable,
  # which is the escape hatch if a UWSM session ever fails to come up: pick the
  # other entry at the greeter instead of editing config from a TTY.
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = builtins.concatStringsSep " " [
        "${pkgs.tuigreet}/bin/tuigreet"
        "--time"
        "--remember" # prefill the last username
        "--remember-session" # and the session it was used with
        "--sessions /run/current-system/sw/share/wayland-sessions"
      ];
      user = "greeter";
    };
  };

  # Extra XDG portal for GTK file pickers / settings (screencast portal comes
  # from Hyprland).
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  # Audio via PipeWire (replaces PulseAudio).
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # System fonts, including a Nerd Font for terminal/bar glyphs.
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-color-emoji
      nerd-fonts.jetbrains-mono
    ];
  };
}
