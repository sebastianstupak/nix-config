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

      # Show the window title in ghostty itself rather than in waybar (which
      # deliberately has no `hyprland/window` module — see waybar.nix).
      #
      # `client` rather than the default `auto`: on Wayland, `auto` prefers
      # SERVER-side decorations wherever the compositor speaks
      # org_kde_kwin_server_decoration, and Hyprland does — but Hyprland's
      # server-side decoration is just a border, it draws no title text. So the
      # title had nowhere to appear. Forcing CSD makes GTK draw a real header bar.
      #
      # With enableZshIntegration above, ghostty tracks the running command, so
      # the header reads `claude`/`nvim`/... per window instead of a static name.
      window-decoration = "client";
      # Second line under the title: which directory this surface is in.
      window-subtitle = "working-directory";
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
