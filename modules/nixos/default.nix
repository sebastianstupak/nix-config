# Aggregates the reusable NixOS modules. Hosts import this single directory.
{
  imports = [
    ./core.nix
    ./desktop.nix
  ];
}
