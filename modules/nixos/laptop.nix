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

  # Backlight / keyboard brightness (used by the Hyprland keybinds in home/).
  environment.systemPackages = with pkgs; [ brightnessctl ];
}
