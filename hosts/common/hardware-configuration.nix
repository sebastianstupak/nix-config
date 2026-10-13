# Hardware shared by BOTH machines (zagreus, hestia) — HAND-MERGED, not generated.
#
# IMPORTANT: this file is no longer raw `nixos-generate-config` output. Two
# physical machines share this one host entry, so it is the union of both:
#
#   - the AMD HP laptop (SanDisk-era WDC PC SN530, 477G)
#   - the Intel SK hynix PC801 machine (954G)
#
# Regenerating it with `nixos-generate-config --show-hardware-config` would
# therefore DESTROY the merge and leave whichever machine you did not run it on
# unbootable. If you ever want generated output back, split the hosts first
# (hosts/<name>/) and give each its own copy.
#
# Everything you actually chose still belongs in hosts/zagreus/default.nix
# or a module — this file is only "what hardware is present".
#
# Deliberate deviations from raw generator output:
#   - `pkgs` is dropped, because it is unused here and the deadnix pre-commit
#     hook (`deadnix --fail`) rejects it;
#   - the stock header pointing at /etc/nixos/configuration.nix is replaced,
#     since no such file exists in a flake-based repo;
#   - filesystems are addressed by LABEL rather than UUID (see below);
#   - initrd modules are the union of both machines' generated lists;
#   - boot.kernelModules is empty and KVM is loaded at runtime from
#     hosts/zagreus/default.nix, because the correct module differs per CPU.
{
  config,
  lib,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  # Union of both machines. Dropping any of these makes the machine that needs
  # it fail to find its root device in the initrd:
  #   nvme, xhci_pci        both
  #   thunderbolt, uas, sd_mod   Intel machine only
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "thunderbolt"
    "uas"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];

  # Empty on purpose. The generator emits "kvm-amd" here on one machine and
  # "kvm-intel" on the other, and a shared host config cannot branch on CPU
  # vendor at evaluation time. Listing both would leave systemd-modules-load
  # permanently failed on whichever machine does not match, so the matching
  # module is probed at runtime instead — see systemd.services.load-kvm in
  # hosts/zagreus/default.nix.
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # BY LABEL, not by UUID. This is the load-bearing change that lets one host
  # config boot two machines: UUIDs are per-filesystem and differ between them,
  # labels are set identically at mkfs time (`mkfs.ext4 -L nixos`,
  # `mkfs.fat -F32 -n BOOT`).
  #
  # The tradeoff worth knowing: if both disks are ever present in the same
  # machine, the labels collide and the initrd may pick the wrong root. Plug
  # the other machine's disk in over USB and mount it by UUID explicitly.
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };

  # Empty: neither machine has a swap partition. Compressed swap in RAM comes
  # from zramSwap in modules/nixos/core.nix, which is not a device and does not
  # belong here. A real swap device (for hibernate) would be added by
  # partitioning and then editing this file by hand — not by regenerating it,
  # see the warning at the top.
  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # Both vendors, because the two machines differ and each option is inert on
  # the CPU it does not match. mkDefault, so the explicit `= true` in
  # modules/nixos/laptop.nix still wins for AMD.
  #
  # The cost is that both microcode packages land in the firmware closure on
  # both machines (~15M). The alternative — leaving only AMD, as the generator
  # produced — means the Intel machine silently receives no microcode updates at
  # all, which is a security and errata problem rather than a disk-space one.
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
