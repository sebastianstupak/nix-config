# System configuration for host "workstation" (HP laptop, daily driver).
# Composes: this host's hardware + the shared NixOS modules + home-manager.
{ inputs, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos
  ];

  networking.hostName = "workstation";

  # Bootloader. systemd-boot assumes UEFI firmware — adjust if you use BIOS/GRUB.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Primary user. Set a password after first boot with `passwd`, or manage it via sops.
  users.users.sebastianstupak = {
    isNormalUser = true;
    description = "Sebastian Stupak";
    shell = pkgs.zsh;
    extraGroups = [
      "wheel" # sudo
      "networkmanager"
      "video" # backlight control
      "audio"
    ];
  };

  # home-manager runs as a NixOS module: one `nixos-rebuild switch` manages the
  # whole machine, with a single generation list and unified rollback.
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs; };
    users.sebastianstupak = import ../../home/sebastianstupak;
  };

  # The NixOS release this system was first installed with.
  # Read the docs before ever changing this — do NOT bump it on upgrades.
  system.stateVersion = "26.05";
}
