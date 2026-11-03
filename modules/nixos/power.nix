# Battery policy: when to warn, when to act, and how the machine goes down.
#
# Split from laptop.nix (which is hardware enablement — networking, bluetooth,
# firmware, microcode) because this file is policy: three percentages and the
# decision of what happens at the last one. The lid switch moved here with it,
# since what the lid does is the same decision.
#
# Nothing watched the battery before this. upower was off, and waybar's battery
# module reads sysfs directly and only recolours — so the machine ran flat with
# no warning and no clean shutdown.
#
# The user-visible warnings live in modules/home/battery.nix and read the
# percentages below through `osConfig`, so the toast, the bar's colour and the
# action cannot drift apart.
#
# See docs/POWER.md for the hibernation story and how to enable it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.power;
in
{
  options.my.power = {
    warnPercentage = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 20;
      description = ''
        First, non-intrusive warning. Also waybar's `warning` state.
      '';
    };

    criticalPercentage = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 10;
      description = ''
        Second warning, sent at critical urgency — swaync never auto-dismisses
        those (`timeout-critical = 0`), so this one stays on screen until it is
        acknowledged. Also waybar's `critical` state.
      '';
    };

    actionPercentage = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 7;
      description = ''
        Where upower stops warning and acts — hibernate if
        {option}`my.power.hibernate.enable`, otherwise a clean poweroff.

        7 rather than the 5 that feels natural: the action has to COMPLETE
        before the battery dies, and writing a RAM-sized hibernation image is
        tens of seconds, during which a 14" laptop under load is still
        draining. 5% can be under three minutes of runtime.
      '';
    };

    remoteAccess = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Keep this machine reachable while nobody is at it.

        A suspended machine is not reachable and cannot be woken: suspending
        drops the WireGuard tunnel, and Wake-on-LAN does not traverse an
        overlay network, so there is nothing left listening to wake it with.
        Whatever was running is unreachable until somebody physically touches
        the laptop — which defeats the entire point of
        {option}`my.remote.enable`.

        So this stops the two things that suspend it unattended: the lid (below)
        and hypridle's idle timer (modules/home/hyprland.nix, which reads this
        through `osConfig`). The 5-minute LOCK is deliberately left alone — the
        machine still locks itself, it just stays awake behind the lock screen,
        and `loginctl unlock-session` over SSH gets you back in.

        SUSPENDING IS THE ONLY THING THE LID BREAKS — it does not turn the
        panel off. That was claimed here for a long time and it is wrong:
        measured on hestia 2026-11-02 over a 32-second lid close, sampled every
        second, eDP-1 stayed `connected`/`enabled`/`dpms=On` and Hyprland kept
        one monitor at `dpmsStatus: 1`, identical to lid-open. Nothing watches
        the lid once this option sets logind to `ignore`, and Hyprland has no
        `switch:Lid Switch` bind of its own. So there is still something to
        capture with the lid shut, and {option}`my.remote.headlessOutput` is not
        needed to create one — see the caveat on that option about why a live
        plane is a separate question from a live connector.

        The cost is a laptop that will flatten its battery if left closed in a
        bag. Two parts to that, and only one has a fix here: the backlight
        burning behind a closed lid is handled by
        {option}`my.power.lidBacklightOff`; the machine staying awake at all is
        inherent, and is the failure hibernation exists to fix.

        BE AWARE THAT HIBERNATION IS NOT AVAILABLE AS AN ESCAPE ON EVERY HOST.
        {option}`my.power.hibernate.enable` asserts an encrypted root, and
        hestia's is plain ext4 — so there the realistic alternatives are "awake
        and reachable" or "plain suspend, unreachable", with no
        suspend-then-hibernate in between.

        And note there is no remote wake SET UP to fall back on. Wake-on-LAN is
        a Layer-2 broadcast and cannot cross the overlay's Layer-3 tunnel, so it
        needs a relay on the target's LAN. This comment used to say no such peer
        exists; that was wrong — apollo's ICE endpoint is `192.168.1.223`, i.e.
        on hestia's LAN. And while hestia has no onboard Ethernet, a USB-C dock
        adds an r8152 NIC, which does implement magic-packet WoL.

        So it is conditionally feasible rather than impossible, and the shaky
        link is USB power across suspend. Untested, and useless away from home
        where there is no relay at all — so a suspended machine should still be
        assumed to stay suspended until somebody touches it. docs/REMOTE.md.

        See {option}`my.power.remoteAccessRequiresAC` for the middle ground,
        which is what both hosts actually use.
      '';
    };

    remoteAccessRequiresAC = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Make {option}`my.power.remoteAccess` apply **only while on mains**: stay
        awake with the lid shut when the charger is in, suspend normally on
        battery.

        This exists because the unconditional version has a real cost and the
        machines are not used the way it assumes. zagreus is the laptop that
        gets carried, and with `remoteAccess` on and nothing to hibernate into
        (plain ext4 root, zram-only swap) a closed lid in a bag runs the battery
        flat — no session lost, but you arrive with a dead laptop.

        THIS REVERSES A DELIBERATE DECISION, so the original reasoning is kept
        rather than deleted. The config used to set both `HandleLidSwitch` and
        `HandleLidSwitchExternalPower` to `ignore` on purpose, arguing that a
        lid which suspends on battery "would make reachability depend on whether
        the charger happened to be in". That is true, and it is now the point:
        the stated usage is charger in, lid closed, permanently. Reachability
        depending on mains is a condition being chosen, not an accident — and
        when the charger is out, the machine is in a bag and being unreachable
        is what you want.

        Set it per host. A machine genuinely used as a desk server, where
        reachability must not depend on a power cable somebody might trip over,
        should leave this off and accept the battery cost.

        Covers both suspend paths, not just the lid:
        - the lid, via logind's native `HandleLidSwitchExternalPower`
        - hypridle's idle timer, which gets the listener back with its command
          guarded by `systemd-ac-power` so it fires only on battery
          (modules/home/hyprland.nix)

        The 5-minute lock is untouched either way, as under `remoteAccess`.
      '';
    };

    wakeOnLan = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "enp1s0" ];
      description = ''
        Wired interfaces to arm for magic-packet Wake-on-LAN, so a suspended
        machine can be woken from its own LAN. Empty disables it.

        This is the other half of {option}`my.power.remoteAccessRequiresAC`:
        that option lets the machine sleep on battery, and this is what can get
        it back without somebody walking over to it. Plugging the charger in
        also wakes it — the AC adapter is already an armed wake source
        (`/sys/devices/platform/ACPI0003:00/power_supply/AC`) — but that needs a
        person in the room, and WoL does not.

        PER HOST, because it depends on hardware that differs. zagreus has
        onboard Realtek Gigabit (`enp1s0`, `r8169`), listed in
        `/proc/acpi/wakeup` as `NIC` and already armed for S5. hestia has no
        built-in Ethernet at all, so there is nothing to set there; docs/REMOTE.md
        covers the USB-dock route and why it is shakier.

        WORTH KNOWING WHAT THIS HAS TO FIGHT, because both would silently undo
        it and both are easy to miss:

        - **TLP disables WoL by default.** Its shipped `defaults.conf` carries
          `WOL_DISABLE=Y`, and nothing here overrode it — so arming the
          interface alone would be reverted by TLP on boot and on every power
          transition. Setting this flips `WOL_DISABLE` to `N`.
        - **NetworkManager can re-apply its own per-connection setting** on
          activation. Its default is to leave the device's existing
          configuration alone, which is why nothing is set for it here — but if
          WoL is armed and still does not survive a reconnect, that is the next
          thing to look at (`nmcli c show <conn> | grep wake-on-lan`).

        UNVERIFIED on this hardware, and honestly so: it needs root to read
        back, a cable in the socket (`/sys/class/net/<iface>/carrier` is `0`
        with none), and a second machine on the LAN to send the packet. Check
        with:

        ```
        sudo ethtool enp1s0 | grep Wake-on     # want: Wake-on: g
        # from apollo or another LAN host, with zagreus suspended:
        wol c0:18:03:5f:6a:3d
        ```

        It only ever helps at home. A laptop on a café network has no peer on
        its LAN to send a magic packet, so the planning assumption away from
        home stays "asleep means unreachable".
      '';
    };

    lidBacklightOff = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Blank the backlight when the lid closes, without touching the output.

        This exists because of what the measurement above found: with
        {option}`my.power.remoteAccess` on, a closed lid changes nothing at all
        — including the backlight, which sits at FULL brightness
        (`intel_backlight` 96000/96000 on hestia) illuminating the inside of a
        shut lid. That is pure waste on a machine deliberately kept awake.

        The obvious fix is the wrong one. `hyprctl dispatch dpms off` or
        disabling the output stops scanout, and scanout is exactly what KMS
        capture reads — so it would trade a lit panel for a broken stream.
        Setting brightness to zero keeps the framebuffer alive and only turns
        the lamp off, which is the one lever that costs nothing.

        Restores the previous brightness on open rather than a fixed value, so
        it does not quietly become a way of resetting how bright your screen is.
      '';
    };

    hibernate = {
      enable = lib.mkEnableOption ''
        suspend-to-disk, so that losing power keeps the session.

        This writes the ENTIRE contents of RAM to the swapfile below —
        /run/secrets (tmpfs, so RAM), the gpg/ssh agent cache, browser
        sessions. On a machine whose root is not encrypted that is a plaintext
        dump of every secret the session has touched, which is why the
        assertion below refuses to let this on without a LUKS device. See
        docs/POWER.md
      '';

      swapSizeMiB = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        example = 32768;
        description = ''
          Size of /swapfile, in MiB. Per-host, because it must be at least this
          machine's RAM: systemd refuses to hibernate when free swap cannot
          hold the image, and the image is bounded by how much memory is in use
          — so RAM-sized is the only size that always works.

          This is NOT general-purpose swap. zramSwap (modules/nixos/core.nix)
          sits at priority 5 and absorbs normal memory pressure; this file is
          pinned to priority 0 so the kernel only reaches it under genuine
          exhaustion, which keeps it free for the hibernation image. systemd
          skips zram devices when choosing where to hibernate, so the two
          cannot fight over the job.
        '';
      };

      allowUnencrypted = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Escape hatch for the assertion that hibernation requires an encrypted
          root. Setting this means accepting that everything in RAM is written
          to an unencrypted disk. Do not set it on a laptop.
        '';
      };
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.warnPercentage > cfg.criticalPercentage;
        message = "my.power.warnPercentage must be above criticalPercentage.";
      }
      {
        assertion = cfg.criticalPercentage > cfg.actionPercentage;
        message = "my.power.criticalPercentage must be above actionPercentage, or the machine acts before it warns.";
      }
      {
        # The security decision, encoded where it cannot be forgotten: a
        # hibernation image is a dump of RAM, and on a plaintext root anyone
        # holding the disk can read it. Checking for a LUKS device is a proxy
        # for "root is encrypted" — not airtight (it would also pass for an
        # encrypted data disk), but it cannot be satisfied by accident, which
        # is what matters for a flag that is otherwise one word to flip.
        assertion =
          !cfg.hibernate.enable || cfg.hibernate.allowUnencrypted || config.boot.initrd.luks.devices != { };
        message = ''
          my.power.hibernate.enable writes all of RAM to /swapfile, and this
          host declares no LUKS device — so the image, including the decrypted
          contents of /run/secrets, would land on a disk anyone can read.

          Encrypt the root first (docs/POWER.md), or set
          my.power.hibernate.allowUnencrypted if you have decided otherwise.
        '';
      }
      {
        assertion = !cfg.hibernate.enable || cfg.hibernate.swapSizeMiB != null;
        message = "my.power.hibernate.enable needs my.power.hibernate.swapSizeMiB set (at least this host's RAM).";
      }
    ];

    # upower, not the user-session script, owns the ACTION. The script in
    # modules/home/battery.nix is a user unit: it does not run at the greeter
    # or after logout, which is exactly when a laptop is left to die
    # unattended. upower is a system service and keeps watching regardless.
    services.upower = {
      enable = true;

      # Default policy is TIME-based (TimeLow/TimeCritical), and the remaining
      # time is an estimate the kernel revises constantly — it swings wildly
      # when load changes. The percentage thresholds below are inert without
      # this.
      usePercentageForPolicy = true;

      percentageLow = cfg.warnPercentage;
      percentageCritical = cfg.criticalPercentage;
      percentageAction = cfg.actionPercentage;

      # upower itself emits no notification — a desktop environment is normally
      # the thing that listens, and Hyprland has nothing playing that role. So
      # these percentages only drive the action; the warnings are ours.
      #
      # PowerOff until hibernation is enabled: it still protects the
      # filesystem from a hard cut, it just cannot keep the session. Note that
      # "Suspend" and "Ignore" are the two values NixOS gates behind
      # allowRiskyCriticalPowerAction; Hibernate and PowerOff are not.
      criticalPowerAction = if cfg.hibernate.enable then "Hibernate" else "PowerOff";
    };

    # Lid: suspend, or suspend-then-hibernate once there is somewhere to
    # hibernate to. The second is the one that actually answers "it died in my
    # bag" — plain suspend keeps draining and loses the session when the
    # battery runs out.
    #
    # Deliberately NOT setting systemd.sleep's HibernateDelaySec. Left unset,
    # systemd uses the ACPI _BTP low-battery alarm to wake the machine and
    # hibernate when the battery approaches 5% (both machines populate
    # /sys/class/power_supply/BAT0/alarm, so the trip point works). Setting a
    # delay DISABLES that path and replaces it with periodic timed wakeups,
    # which both drains more and hibernates on a clock rather than on need.
    #
    # THREE states, not two, and the middle one is what both hosts use.
    #
    # my.power.remoteAccess alone overrides BOTH of these to "ignore". The
    # original argument for that: closing the lid of a machine you intend to
    # connect to is a normal thing to do — it is how a laptop sits on a desk
    # when it is being used as a server — and a lid that suspends on battery
    # would make reachability depend on whether the charger happened to be in.
    #
    # That reasoning is sound and was the wrong trade for these machines. The
    # dependency it warns about is now deliberate: see
    # my.power.remoteAccessRequiresAC, which keeps reachability on mains and
    # hands the lid back on battery, because a carried laptop with no
    # hibernation target otherwise flattens itself in a bag.
    services.logind.settings.Login =
      let
        # Nothing to hibernate into on either host today (ext4 root, zram-only
        # swap), so this resolves to plain "suspend" — but keep it derived so
        # enabling hibernation fixes the lid everywhere at once.
        onBattery = if cfg.hibernate.enable then "suspend-then-hibernate" else "suspend";
      in
      if cfg.remoteAccess && !cfg.remoteAccessRequiresAC then
        {
          HandleLidSwitch = "ignore";
          HandleLidSwitchExternalPower = "ignore";
        }
      else if cfg.remoteAccess then
        {
          # The whole point: reachable with the lid shut while plugged in,
          # asleep in a bag. systemd distinguishes these natively, so this needs
          # no polling and no script — the kernel's power-supply state decides.
          HandleLidSwitch = onBattery;
          HandleLidSwitchExternalPower = "ignore";
        }
      else
        {
          HandleLidSwitch = onBattery;

          # On AC, closing the lid should not start a countdown to hibernation —
          # the battery is not the constraint. (systemd's own default, set
          # explicitly so it does not quietly follow HandleLidSwitch above.)
          HandleLidSwitchExternalPower = "suspend";
        };

    # --- Wake-on-LAN --------------------------------------------------------
    # Two settings, because arming the NIC is not enough on a machine running
    # TLP: its defaults.conf ships WOL_DISABLE=Y, so it would strip the flag
    # back off at boot and on every power transition. Found by reading TLP's
    # defaults rather than by it failing, since the failure mode is a machine
    # that simply never wakes and gives no indication why.
    #
    # mkIf on both so a host that sets no interfaces neither flips a TLP
    # setting nor declares an empty networking.interfaces entry.
    services.tlp.settings.WOL_DISABLE = lib.mkIf (cfg.wakeOnLan != [ ]) "N";

    # NixOS's own option rather than a hand-rolled ethtool unit: it writes a
    # systemd .link file, which systemd-udevd applies — see docs/REMOTE.md for
    # why that works with networkd disabled.
    networking.interfaces = lib.genAttrs cfg.wakeOnLan (_: {
      wakeOnLan.enable = true;
    });

    # ethtool, because WoL is otherwise UNFALSIFIABLE on this machine. The
    # kernel exposes no sysfs attribute for the magic-packet flag — the PCI
    # `power/wakeup` file is a different thing — so `ethtool <iface> | grep
    # Wake-on` is the only way to read back whether any of the above worked.
    # It is not pulled in by `networking.interfaces.*.wakeOnLan`, which needs
    # no runtime tool, so arming WoL without this ships a feature whose state
    # cannot be inspected. Found the obvious way: reaching for ethtool to check
    # and discovering `command not found`.
    environment.systemPackages = lib.mkIf (cfg.wakeOnLan != [ ]) [ pkgs.ethtool ];

    # AND LOGIND HAS TO BE TOLD TO RE-READ IT, or everything above is a file on
    # disk that nothing acts on.
    #
    # nixpkgs ships systemd-logind with restartIfChanged = false — restarting it
    # would tear down the graphical session — but it also leaves
    # reloadIfChanged at the global default of false, so a switch writes the new
    # logind.conf and the RUNNING daemon keeps the old values until the next
    # reboot. That was not theoretical: after the switch that introduced
    # my.power.remoteAccess, /etc/systemd/logind.conf said
    # `HandleLidSwitch=ignore` while logind still answered "suspend" on D-Bus,
    # six days into its uptime. The lid would have kept suspending a machine
    # whose whole configuration said it should not.
    #
    # Reload rather than restart, which is the part that makes this safe:
    # logind advertises CanReload=yes and re-reads its configuration in place,
    # without dropping sessions. Verify after a switch with
    #   busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
    #     org.freedesktop.login1.Manager HandleLidSwitch
    #
    # AND reloadIfChanged ON ITS OWN IS NOT ENOUGH — it only says HOW to apply a
    # change, never that one happened. switch-to-configuration decides a unit
    # needs attention by diffing the unit file and its X-Restart-Triggers, and
    # logind.conf is neither: it is a plain `environment.etc` entry the unit has
    # no declared relationship with. So a switch that changes ONLY logind.conf
    # leaves the running daemon untouched and reports nothing.
    #
    # Caught 2026-11-03, the same bug from the other direction and after it was
    # supposedly fixed: the switch that introduced remoteAccessRequiresAC wrote
    # `HandleLidSwitch=suspend` to disk while logind still answered "ignore" on
    # D-Bus, so the battery protection the whole change exists for was not live
    # and nothing said so. Naming the file as a trigger is what closes it —
    # combined with reloadIfChanged above, a changed logind.conf now produces a
    # reload instead of a restart or a silent no-op.
    systemd.services.systemd-logind = {
      reloadIfChanged = true;
      restartTriggers = [ config.environment.etc."systemd/logind.conf".source ];
    };

    # The hibernation target. One file inside the root filesystem, so it is
    # covered by whatever encrypts root — which is the entire reason this is
    # a swapFILE and not a swap partition.
    #
    # No `resume_offset` and no boot.resumeDevice: with
    # boot.initrd.systemd.enable (already on here), systemd-sleep picks the
    # swap area itself and records it in the HibernateLocation EFI variable,
    # which systemd-hibernate-resume reads at boot. The old filefrag dance is
    # only needed for a scripted initrd — docs/POWER.md keeps it as a fallback.
    swapDevices = lib.mkIf cfg.hibernate.enable [
      {
        device = "/swapfile";
        size = cfg.hibernate.swapSizeMiB;
        priority = 0; # below zram's 5 — see swapSizeMiB above
      }
    ];
  };
}
