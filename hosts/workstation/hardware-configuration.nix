# PLACEHOLDER — DO NOT DEPLOY AS-IS. This will NOT boot a real machine.
#
# Generate the real file ON THE TARGET LAPTOP, after installing NixOS, with:
#
#     sudo nixos-generate-config --show-hardware-config \
#       > hosts/workstation/hardware-configuration.nix
#
# then `git add` and commit it. This file is machine-specific and MUST be
# committed — untracked files are invisible to flake evaluation (see AGENTS.md).
#
# The stubs below only exist so the flake can be *evaluated* on another machine.
{ lib, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [ ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # Replace with your real root filesystem.
  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # Replace with your real EFI system partition.
  fileSystems."/boot" = lib.mkDefault {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
  };

  swapDevices = [ ];

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
