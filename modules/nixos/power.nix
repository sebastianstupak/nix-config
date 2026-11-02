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
{ config, lib, ... }:
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
    # my.power.remoteAccess overrides BOTH of these to "ignore" rather than
    # just the on-battery one. Closing the lid of a machine you intend to
    # connect to is a normal thing to do — it is how a laptop sits on a desk
    # when it is being used as a server — and a lid that suspends on battery
    # would make reachability depend on whether the charger happened to be in.
    services.logind.settings.Login =
      if cfg.remoteAccess then
        {
          HandleLidSwitch = "ignore";
          HandleLidSwitchExternalPower = "ignore";
        }
      else
        {
          HandleLidSwitch = if cfg.hibernate.enable then "suspend-then-hibernate" else "suspend";

          # On AC, closing the lid should not start a countdown to hibernation —
          # the battery is not the constraint. (systemd's own default, set
          # explicitly so it does not quietly follow HandleLidSwitch above.)
          HandleLidSwitchExternalPower = "suspend";
        };

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
    systemd.services.systemd-logind.reloadIfChanged = true;

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
