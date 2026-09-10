# Terminal emulator: Ghostty (GPU-accelerated, native Wayland, great Nix module).
# Install from nixpkgs (not the upstream flake) to avoid Wayland/OpenGL ABI
# issues; the system enables hardware.graphics so the desktop-launch GL path works.
{ ... }:
{
  programs.ghostty = {
    enable = true;
    enableZshIntegration = true;
    installVimSyntax = true;
    settings = {
      font-family = "JetBrainsMono Nerd Font";
      font-size = 12;
      background-opacity = 0.95;
      # theme is set by the theming layer (Stylix/Catppuccin) once chosen;
      # until then Ghostty uses its built-in default.
    };
  };
}
