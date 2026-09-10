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
    ./git.nix
    ./dev.nix
    ./hyprland.nix
  ];

  # Let home-manager manage itself.
  programs.home-manager.enable = true;
}
