# Baseline NixOS config every host imports. Machine-specific profiles
# (desktop.nix, laptop.nix, containers.nix) are opted into per host, so a
# future server can take the baseline without a desktop or laptop power stack.
{
  imports = [
    ./core.nix
  ];
}
