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

      # Always open in $HOME. Ghostty 1.2+ runs as a single-instance systemd
      # user service, so new windows are spawned by a long-lived daemon and
      # `window-inherit-working-directory` (default true) wins over
      # `working-directory` — inheriting whatever the last focused surface had
      # (typically ~/nix-config). Both must be set. Trade-off: new tabs/splits
      # no longer inherit the current directory either; there is no upstream
      # knob to separate the two (ghostty-org/ghostty#9438).
      working-directory = "home";
      window-inherit-working-directory = false;
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
