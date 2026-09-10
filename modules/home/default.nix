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
    ./hyprland.nix
    ./waybar.nix
    ./calendar.nix
    ./mono-icons.nix
  ];

  # Let home-manager manage itself.
  programs.home-manager.enable = true;
}
