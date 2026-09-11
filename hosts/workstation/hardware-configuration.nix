# Machine-specific hardware for host "workstation" — GENERATED, not hand-written.
#
# Regenerate on this machine (no sudo needed) and commit the result:
#
#     nixos-generate-config --show-hardware-config \
#       > hosts/workstation/hardware-configuration.nix
#
# Do not hand-edit. Anything you actually chose belongs in
# hosts/workstation/default.nix or a module, or it is lost on the next
# regeneration. statix.toml excludes this path from linting for that reason;
# `nix fmt` does still format it, and the `formatting` check requires it.
#
# Two deliberate deviations from raw generator output:
#   - the `pkgs` argument is dropped, because it is unused here and the
#     deadnix pre-commit hook (`deadnix --fail`) rejects it;
#   - the stock header pointing at /etc/nixos/configuration.nix is replaced,
#     since no such file exists in a flake-based repo.
#
# Everything below was verified against the running machine before committing:
# both UUIDs resolve to the expected partitions (/ -> nvme0n1p2,
# /boot -> nvme0n1p1) and both initrd modules are loaded.
{
  config,
  lib,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/a14419bc-2ddc-453f-a029-362eab9653fa";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/CB59-E4E4";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };

  # Empty: this machine has no swap partition. Compressed swap in RAM comes from
  # zramSwap in modules/nixos/core.nix, which is not a device and does not belong
  # here. A real swap device (for hibernate) would be added by regenerating this
  # file after partitioning.
  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # mkDefault, so the explicit `= true` in modules/nixos/laptop.nix wins. Kept
  # rather than deleted: it is what the generator emits, and on a host that does
  # not import laptop.nix it is the thing that enables microcode at all.
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
