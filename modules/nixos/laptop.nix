# Laptop hardware & power: networking, power management, bluetooth, firmware, backlight.
{ pkgs, ... }:
{
  # Wi-Fi / wired networking for a laptop.
  networking.networkmanager.enable = true;

  # ONE ADDRESS PER SUBNET: stand the wifi radio down while a cable is in.
  #
  # This is not tidiness or power saving. Holding two addresses on
  # 192.168.1.0/24 at once is what made Moonlight disconnect every few minutes,
  # and the mechanism took three wrong diagnoses to find, so it is written out
  # in full. Measured on zagreus, docked:
  #
  #   netbird's WireGuard socket:  0.0.0.0:51821              (ONE unbound socket)
  #   negotiated ICE local cand.:  192.168.1.191              (wlp2s0, wifi)
  #   ip route get <client>:       dev enp1s0 src 192.168.1.241 (ethernet)
  #
  # One socket, two addresses on one subnet, and a route that prefers the
  # Ethernet one (metric 100 vs 600). So NetBird gathers and signals a host
  # candidate on the WIFI address, while every packet the kernel actually sends
  # leaves from the ETHERNET address. The peer therefore sees traffic from an
  # address that was never signalled and files it as **peer-reflexive** —
  # `netbird status -d` reads `ICE candidate (Local/Remote): host/prflx` — and
  # an ICE pair built on reflexive guesses instead of the signalled ones never
  # settles. It re-validates, fails, and restarts every few minutes.
  #
  # The damage, which is why a stream feels it and SSH does not: each restart
  # resets the WireGuard endpoint and falls back to a relay until a new path is
  # agreed. Holes of 33 s, 129 s, 180 s and 31 s were measured inside half an
  # hour. SSH rides that out; a video stream does not, and both endpoints give
  # up long before three minutes (docs/REMOTE.md has the timings).
  #
  # Ruled out first, each at some cost: broken IPv6 RAs (real, fixed, and NOT
  # this), Sunshine's `ping_timeout` (raised, did not help — no host-side value
  # out-waits a 3-minute hole), and NetBird's Management stream dropping every
  # ~21 minutes, which turned out to be NORMAL — hestia shows the identical
  # 20.5-minute beat, so it is a server-side connection max-age and not a
  # gateway fault. The gateway needs no changes for any of this.
  #
  # TLP's Radio Device Wizard already ships the dispatcher hook that does this
  # (`/etc/NetworkManager/dispatcher.d/99tlp-rdw-nm`, installed by
  # `services.tlp.enable`); it just has no policy set, because both lists
  # default to empty. Using it beats a hand-rolled script: it is time-locked
  # against event storms, it retries when NetworkManager is asleep, it ignores
  # virtual interfaces, and it is driven by NetworkManager rather than polling.
  #
  # Correct on BOTH machines. hestia docks to a USB-C NIC and the docs already
  # recorded docking knocking its peers onto a relay — same cause, same fix.
  #
  # The cost: unplugging now means a wifi re-association (a few seconds offline)
  # instead of an instant failover to an already-associated link. Worth it
  # against a stream that breaks every few minutes.
  services.tlp.settings = {
    DEVICES_TO_DISABLE_ON_LAN_CONNECT = "wifi";
    DEVICES_TO_ENABLE_ON_LAN_DISCONNECT = "wifi";
  };

  # The failsafe the setting above needs to be safe on a laptop.
  #
  # TLP switches the radio through `nmcli radio wifi off`, and NetworkManager
  # PERSISTS that in /var/lib/NetworkManager/NetworkManager.state. So shutting
  # down while docked and booting somewhere else leaves the radio off with no
  # cable and no dispatcher event coming to turn it back on — a laptop with no
  # network and no obvious reason why. TLP will not save you here either:
  # `RESTORE_DEVICE_STATE_ON_STARTUP` defaults to 0.
  #
  # So assert the invariant at boot instead of trusting the event stream: the
  # radio may only be off while a cable is actually connected. Carrier is read
  # from sysfs rather than asked of NetworkManager, because at this point in
  # boot NM may not have finished DHCP on a link that is plainly plugged in.
  #
  # Costs nothing in the normal case — if the radio is already on it exits
  # before doing any work, which is every boot except the one this exists for.
  systemd.services.wifi-radio-failsafe = {
    description = "Re-enable the wifi radio unless a cable is connected";
    wants = [ "NetworkManager.service" ];
    after = [ "NetworkManager.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
    };
    script = ''
      nmcli=${pkgs.networkmanager}/bin/nmcli

      # Wait for NetworkManager's D-Bus API, not just its unit, then bail out
      # immediately if the radio is already on — the overwhelmingly common case.
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        radio=$("$nmcli" -t radio wifi 2>/dev/null) && break
        sleep 1
      done
      [ "''${radio:-enabled}" = "enabled" ] && exit 0

      # Radio is off. That is only legitimate while something wired has
      # carrier. Retry briefly: a cable present at boot can take a moment to
      # report, and guessing "no cable" too early would re-enable wifi on a
      # docked machine, recreating the dual-homing this is all about.
      #
      # "Wired" is `$dev/device` + `type` 1 + not wireless, and the first of
      # those is load-bearing: it is the symlink to the backing PCI/USB device,
      # so only REAL NICs have it. Naming patterns and `tun_flags` both fail
      # here — wt0 is a WireGuard device, which has no tun_flags and sits at
      # carrier=1 permanently, so an earlier version of this read the overlay
      # as a cable and would have stranded the radio off exactly when this
      # failsafe was supposed to fire. Keeps hestia's USB-C dock NIC (a real
      # USB device, type 1) and drops lo, wt0 and the podman bridges.
      for _ in 1 2 3 4 5; do
        for dev in /sys/class/net/*; do
          [ -e "$dev/device" ] || continue
          [ -e "$dev/wireless" ] && continue
          [ "$(cat "$dev/type" 2>/dev/null)" = "1" ] || continue
          if [ "$(cat "$dev/carrier" 2>/dev/null)" = "1" ]; then
            echo "wired carrier on ''${dev##*/}; leaving the wifi radio off"
            exit 0
          fi
        done
        sleep 1
      done

      echo "no wired carrier and the wifi radio is off; re-enabling it"
      "$nmcli" radio wifi on
    '';
  };

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
  # power/control=on forever and never suspended, which sent a whole round of
  # "disable the dGPU" work chasing the driver instead of the pin.
  #
  # Flipping this moved 26 PCI devices from "on" to "auto" and the dGPU from
  # `active` to `suspended` within seconds, WITH NO DRIVER BOUND TO IT — which
  # is also what disproved the received wisdom that an unbound Optimus card
  # cannot power down. See hosts/hestia/default.nix for the numbers.
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
