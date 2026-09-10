# Graphical session: Hyprland (Wayland) + login manager, portals, audio, fonts.
# The per-user Hyprland/waybar/etc. config lives in home/ (modules/home/hyprland.nix).
{ pkgs, ... }:
{
  # Hyprland compositor. Provides the Wayland session and pulls in the
  # hyprland xdg-desktop-portal automatically.
  programs.hyprland.enable = true;

  # Login manager: greetd + tuigreet, launching Hyprland directly.
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd Hyprland";
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
      noto-fonts-emoji
      nerd-fonts.jetbrains-mono
    ];
  };
}
