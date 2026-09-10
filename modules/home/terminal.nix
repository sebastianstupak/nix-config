# Terminal emulator: kitty (GPU-accelerated, first-class Wayland support).
{ ... }:
{
  programs.kitty = {
    enable = true;
    font = {
      name = "JetBrainsMono Nerd Font";
      size = 12;
    };
    settings = {
      enable_audio_bell = false;
      confirm_os_window_close = 0;
      background_opacity = "0.95";
    };
  };
}
