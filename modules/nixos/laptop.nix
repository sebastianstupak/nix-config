# Laptop hardware & power: networking, power management, bluetooth, firmware, backlight.
{ pkgs, ... }:
{
  # Wi-Fi / wired networking for a laptop.
  networking.networkmanager.enable = true;

  # Power management. TLP generally gives the best battery life on laptops;
  # it conflicts with power-profiles-daemon, so disable that.
  services.power-profiles-daemon.enable = false;
  services.tlp.enable = true;
  powerManagement.enable = true;

  # Suspend when the lid closes.
  services.logind.settings.Login.HandleLidSwitch = "suspend";

  # Bluetooth + a tray applet (Hyprland ships no built-in one).
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;

  # Firmware updates: `fwupdmgr refresh && fwupdmgr update`.
  services.fwupd.enable = true;

  # CPU microcode (AMD; this machine reports k10temp/amdgpu). Normally
  # nixos-generate-config writes this line into hardware-configuration.nix — but
  # that file is still the committed PLACEHOLDER, so nothing was setting it and
  # the machine has been running on factory microcode with no errata or
  # security updates. Set here rather than waiting for the real hardware config,
  # because it is a security fix and does not depend on this machine's disks.
  #
  # Needs hardware.enableRedistributableFirmware (already true) — the ucode blob
  # is redistributable-but-unfree. Delivered via initrd, so it needs a reboot,
  # not just a switch. Harmless to keep once the real hardware config lands: that
  # file sets the same option with mkDefault.
  hardware.cpu.amd.updateMicrocode = true;

  # Backlight / keyboard brightness (used by the Hyprland keybinds in home/).
  environment.systemPackages = with pkgs; [ brightnessctl ];
}
