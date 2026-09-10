# Aggregates the reusable home-manager modules. Per-user config (identity, host
# specifics) lives in home/<user>/.
{
  imports = [
    ./shell.nix
    ./cli.nix
    ./terminal.nix
    ./editor.nix
    ./browsers.nix
    ./office.nix
    ./proton.nix
    ./media.nix
    ./comms.nix
    ./git.nix
    ./git-hooks.nix
    ./security.nix
    ./dev.nix
    ./claude-code.nix
    ./hyprland.nix
    ./waybar.nix
    ./notifications.nix
    ./calendar.nix
    ./mono-icons.nix
  ];

  # Let home-manager manage itself.
  programs.home-manager.enable = true;
}
