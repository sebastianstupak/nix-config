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

  # PCIe autosuspend ON AC TOO, which is not TLP's default and is the only
  # reason anything idle can actually power down while plugged in.
  #
  # Unset, RUNTIME_PM_ON_AC is "on" — devices held awake permanently on AC. That
  # is the conservative choice and it is usually invisible, but on hestia it was
  # load-bearing in the wrong direction: the discrete RTX A500 read
  # power/control=on forever, so nothing ever invoked its ACPI power-off, and a
  # whole round of "disable the dGPU" work changed nothing because the pinning
  # was the actual cause (see hosts/hestia/default.nix).
  #
  # "auto" only PERMITS the kernel to suspend an idle device; it does not force
  # anything. The documented risk is hardware that misbehaves when autosuspended
  # — if something flaky turns up, exclude that one device via
  # RUNTIME_PM_DENYLIST rather than reverting this, because the global pin is
  # what hid the problem in the first place.
  #
  # Both machines: zagreus is all-AMD with nothing exotic on its bus, and the
  # setting is equally correct there. Check what it actually did with
  # `tlp-stat -p`, or per-device under /sys/bus/pci/devices/*/power/control.
  services.tlp.settings.RUNTIME_PM_ON_AC = "auto";

  # What the lid does, when to warn about the battery and what happens when it
  # runs out are all policy rather than hardware enablement — modules/nixos/power.nix.

  # Bluetooth + a tray applet (Hyprland ships no built-in one).
  hardware.bluetooth = {
    enable = true;

    # Adapter stays off until something asks for it. On by default means the
    # laptop announces itself on every network it wakes up on, for a radio that
    # is idle most days — `bluetoothctl power on`, or the bar's applet, brings
    # it up when there is actually something to pair with.
    powerOnBoot = false;

    # Battery levels for connected devices (headphones, mice). BlueZ only exposes
    # org.bluez.Battery1 with Experimental on — without it the D-Bus property
    # simply is not there, so nothing can report a headphone as 40%. That is what
    # feeds the tooltip of waybar's `bluetooth` module (modules/home/waybar.nix).
    #
    # "Experimental" here means BlueZ's not-yet-stable D-Bus interfaces, not
    # unstable code paths in the daemon; battery reporting has lived behind this
    # flag for years and enabling it is the normal way to get it.
    settings.General.Experimental = true;
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
