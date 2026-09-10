# Terminal: Ghostty (GPU-accelerated, native Wayland, great Nix module) + zellij
# as the multiplexer. Install ghostty from nixpkgs (not the upstream flake) to
# avoid Wayland/OpenGL ABI issues; the system enables hardware.graphics so the
# desktop-launch GL path works.
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
      # colors/fonts are driven by the Stylix theming layer.
    };
  };

  # Terminal multiplexer. Shell integration is intentionally OFF — enabling it
  # auto-starts zellij on every interactive shell; launch it deliberately instead.
  programs.zellij = {
    enable = true;
    enableZshIntegration = false;
    settings = {
      pane_frames = false;
    };
  };
}
