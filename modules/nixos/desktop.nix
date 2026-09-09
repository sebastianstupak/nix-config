# Laptop desktop stack. NetworkManager + PipeWire are enabled; the actual desktop
# environment is left for you to choose — uncomment ONE block below, then rebuild.
{ ... }:
{
  # Laptop networking.
  networking.networkmanager.enable = true;

  # Audio via PipeWire (the modern default; replaces PulseAudio).
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # --- Choose a desktop environment (uncomment one) -----------------------

  # GNOME on Wayland:
  # services.xserver.enable = true;
  # services.displayManager.gdm.enable = true;
  # services.desktopManager.gnome.enable = true;

  # KDE Plasma 6:
  # services.displayManager.sddm.enable = true;
  # services.desktopManager.plasma6.enable = true;

  # ------------------------------------------------------------------------
}
