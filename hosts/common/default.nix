# Everything both machines share.
#
# Split out of hosts/zagreus/ when the second machine stopped being able to
# share one host entry. A single nixosConfiguration can only produce one
# `networking.hostName` and one `hashedPasswordFile`, and Nix cannot branch on
# which machine is evaluating it — so per-machine identity and per-machine
# secrets force separate hosts. Everything that is genuinely common lives here,
# and each host adds only what distinguishes it.
{
  config,
  inputs,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos # baseline (core)
    ../../modules/nixos/desktop.nix # Hyprland graphical session
    ../../modules/nixos/stylix.nix # system-wide theming (Kanagawa)
    ../../modules/nixos/laptop.nix # power, bluetooth, firmware, backlight
    ../../modules/nixos/power.nix # battery thresholds, lid, hibernation (docs/POWER.md)
    ../../modules/nixos/containers.nix # rootless podman
    ../../modules/nixos/netbird.nix # mesh VPN
    ../../modules/nixos/remote.nix # SSH + Sunshine over the overlay (docs/REMOTE.md)
    ../../modules/nixos/backup.nix # restic (inert until my.backup.repository is set)
    ../../modules/nixos/syncthing.nix # peer-to-peer sync (inert until my.syncthing.enable)
    # Pro-audio + Ableton via shibco/ableton-linux. Measured before enabling:
    # 54 derivations built and 587 fetched (917 MiB), of which only
    # ableton-wine and ableton-linkd are real from-source builds — that flake
    # pins its own nixos-unstable, which cache.nixos.org already covers, so the
    # "big from-source build" this import was parked for is mostly just Wine.
    ../../modules/nixos/audio.nix # inert until my.ableton.enable below
    ../../modules/nixos/gaming.nix # inert until my.gaming.enable below
  ];

  # Pro-audio + Ableton Live. Opt-in rather than implied by the import, because
  # it changes the kernel command line (threadirqs), loads a boot-time module
  # (ntsync) and grants the audio group realtime scheduling — none of which
  # should arrive on a host as a side effect of importing a file. See
  # docs/ABLETON.md.
  my.ableton.enable = true;

  # Steam/Proton, Lutris, and Prism Launcher for Minecraft. Opt-in for the same
  # reason as above: it brings in a whole second 32-bit graphics stack, which is
  # not something a machine should acquire by importing a file. See
  # docs/GAMING.md.
  my.gaming.enable = true;

  # Remote access, so one machine can drive another: SSH for terminals (which is
  # what `herdr` sessions are reached over — modules/home/herdr.nix) and
  # Sunshine for the desktop. Shared, because the useful arrangement is every
  # machine reachable from every other; the mechanism and the reasoning about
  # scoping it to the overlay live in modules/nixos/remote.nix, and the
  # first-time pairing walkthrough in docs/REMOTE.md.
  my.remote = {
    enable = true;

    # wayvnc as well as Sunshine, because the fleet includes a Mac as a TARGET
    # and Sunshine cannot serve one properly — Experimental upstream, no
    # Command key, and no virtual display so a closed lid has nothing to
    # capture. VNC is the only protocol with a first-class host on Hyprland,
    # Windows AND macOS (where it is built in). Sunshine stays the default for
    # the machines it is good on; this is what makes one client reach them all.
    # Protocol matrix and per-OS setup: docs/REMOTE.md.
    vnc.enable = true;

    # Both machines are desktops that connect to each other, not just targets.
    # Without this neither could open the other's screen — see the option's
    # description in modules/nixos/remote.nix.
    clients.enable = true;

    # Client keys. One line per machine you connect FROM — add the Windows and
    # macOS ones here as they appear, rather than appending to
    # ~/.ssh/authorized_keys on each host and losing it at the next reinstall.
    authorizedKeys = [
      # hestia (HP ZBook Firefly 14 G10) — ~/.ssh/id_ed25519.pub
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIECIb5oKGEB0UvtftQq+jaZb4L31w5ETVliC3NsFQAc7 sebastianstupak@datadir.co"
      # apollo (Windows 11) — C:/Users/sebas/.ssh/aur_new.pub
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILxiZkJYemqt/AiVZhgY9l6Jdf/AFSWkWWERngflKmNs sebastian.stupak@pm.me"
      # zagreus (AMD HP laptop) — ~/.ssh/id_ed25519.pub. NOTE the key comment is
      # the same `sebastian.stupak@pm.me` as apollo's above and the key material
      # is different — the comment is not an identifier, so match on the base64
      # when auditing this list rather than on the trailing address.
      # Until this was added, zagreus could not SSH OUT to the others at all;
      # agent forwarding is off deliberately, so every machine needs its own.
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBbBMM/Qy7hv3F/W42k2xWl25aybbqC+hddWVb8AdE+J sebastian.stupak@pm.me"
    ];

    # Peer HOST keys, so there is never a trust-on-first-use prompt to click
    # through. Get a new machine's with `cat /etc/ssh/ssh_host_ed25519_key.pub`
    # ON that machine, and its overlay name and address from `netbird status`.
    # The overlay FQDN is `<peer name>.netbird.cloud`, and the peer name is NOT
    # the hostname — it is whatever the machine was called when it enrolled,
    # and NetBird never updates it afterwards. Both of these enrolled while
    # they still shared the name `workstation`, so NetBird disambiguated them
    # by appending part of the overlay IP: `workstation-98-165.netbird.cloud`.
    # Renamed in the dashboard to match the hostnames; rename there, not here,
    # if a machine ever needs it again.
    peers = {
      hestia = {
        hostNames = [
          "hestia.netbird.cloud"
          "100.94.198.156"
        ];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBAyCoT427eImjRO7gZhcsx4ylFzunEbDOLlcPXxC9gv workstation-intel";
      };

      # zagreus re-enrolled on the setup key 2026-11-02, which is why its name
      # needed no dashboard rename: a fresh peer takes its name from the
      # hostname, and the hostname is now `zagreus`. The address below is NOT
      # the one this comment used to advertise (100.94.242.62) — deleting the
      # peer to escape its expired SSO session is what changed it, and a new
      # overlay IP is the price of that. The FQDN survived, so prefer it.
      #
      # The key comment still reads `root@workstation` because host keys are
      # generated at install and never regenerated by a rename. Same situation
      # as hestia's `workstation-intel` above. Leave them; rewriting the comment
      # would not change the key, and a reinstall is the only thing that does.
      zagreus = {
        hostNames = [
          "zagreus.netbird.cloud"
          "100.94.40.180"
        ];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHThhuThkvZY2NC3M9WYlDYtO+MTSFdGYUhmDX9WFsSG root@workstation";
      };
    };
  };

  # Stay reachable: no suspend on lid close, no suspend on idle. This is the
  # half of my.remote that lives in the power module, because a suspended
  # machine cannot be woken over an overlay network — see my.power.remoteAccess
  # and docs/POWER.md.
  my.power.remoteAccess = true;

  # BUT ONLY ON MAINS, which is the difference between reachable and ruined.
  # These are laptops, not desk servers: the stated use is charger in and lid
  # closed, so mains is the normal state and reachability costs nothing — while
  # unplugging means the machine is going in a bag, where `remoteAccess` on its
  # own would run the battery flat with no hibernation target to fall back on
  # (ext4 root, zram-only swap on both hosts).
  #
  # This deliberately makes reachability depend on the charger being in, which
  # modules/nixos/power.nix once argued against. That argument is preserved
  # there alongside why it no longer applies. Turn this OFF for a host that must
  # stay reachable regardless of a power cable somebody might unplug.
  my.power.remoteAccessRequiresAC = true;

  # The lid still blanks the panel in every case, including the mains case where
  # it no longer suspends — measured, not assumed: a 32-second lid close changed
  # nothing, down to the backlight sitting at full brightness lighting the inside
  # of a shut lid. This turns the lamp off and deliberately leaves the output
  # scanning out, so KMS capture keeps working with the lid down. See
  # my.power.lidBacklightOff.
  my.power.lidBacklightOff = true;

  # Backups. One shared restic repository for every machine here — restic
  # deduplicates across the whole thing, so the licensed artifacts and dotfiles
  # that are identical on several machines cost storage once. Snapshots carry
  # the hostname and `forget` groups by it, so each machine keeps its own
  # history — which only became true once the machines stopped sharing a
  # hostname.
  #
  # `prune` is NOT set here. It takes an exclusive lock on the repository, so it
  # has to be exactly one machine, and a shared default is how it became all of
  # them. The host that prunes says so itself.
  #
  # The repository is in a Scaleway organization of its own, not the company's,
  # and the key that reaches it is scoped to that one project — a stolen laptop
  # cannot use it to touch anything else. restic encrypts client-side, so the
  # provider stores ciphertext either way.
  my.backup.repository = "s3:https://s3.fr-par.scw.cloud/sstupak-restic-backups";

  # Peer-to-peer sync with my own devices (currently the Boox Note Air 4C,
  # which carries sheet music as .mscz). No cloud provider and no long-lived
  # credential on the tablet, which matters for a device that is easy to lose.
  # Synced folders live under $HOME, so restic above picks them up — Syncthing
  # replicates deletions, so it is not itself a backup.
  my.syncthing.enable = true;

  # Bootloader. systemd-boot assumes UEFI firmware — adjust if you use BIOS/GRUB.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Cap boot entries. The ESP here is 1G and each distinct kernel+initrd pair in
  # it costs ~24M, so an uncapped list is a slow leak on a machine that gets
  # rebuilt a dozen times a day. nix.gc prunes system generations after 30 days,
  # which bounds it eventually — but the failure mode if it ever does fill is a
  # switch that dies partway through writing the ESP, which is a bad place to be
  # stranded. 20 keeps well over a month of rollback targets.
  boot.loader.systemd-boot.configurationLimit = 20;

  # Load whichever KVM module matches this CPU.
  #
  # The two machines differ in CPU vendor and still share this file, so
  # boot.kernelModules cannot name the module: listing both leaves
  # systemd-modules-load permanently failed on whichever machine does not
  # match, and listing one silently denies hardware virtualisation to the
  # other. Neither module has a reliable sysfs modalias to autoload from on
  # this kernel (/sys/devices/system/cpu/cpu0/modalias does not exist), so
  # probe both and let the wrong one fail harmlessly.
  #
  # `|| true` is deliberate: exactly one of these two always fails with ENODEV,
  # and that is the expected steady state, not an error worth a degraded unit.
  systemd.services.load-kvm = {
    description = "Load the KVM module matching this CPU";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.kmod}/bin/modprobe kvm_amd 2>/dev/null \
        || ${pkgs.kmod}/bin/modprobe kvm_intel 2>/dev/null \
        || true
    '';
  };

  # Users are fully declarative: nothing here is created or changed with
  # `useradd`/`passwd`, and anything NOT declared is removed on activation.
  #
  # This is what makes hashedPasswordFile authoritative — update-users-groups.pl
  # applies a declarative hash to an EXISTING user only when mutableUsers is
  # false (`$sp_pwdp = ... if defined $u->{hashedPassword} && !$spec->{mutableUsers}`).
  # With it true the hash sat there inert, which is how it was staged safely.
  #
  # The consequence worth remembering: `passwd` no longer changes your password.
  # Rotating it means writing a new hash into this host's passwords file and
  # rebuilding — see secrets/README.md.
  users.mutableUsers = false;

  # Primary user.
  #
  # `hashedPasswordFile` points at a secret each HOST declares, not one declared
  # here, so the machines can hold different passwords. A missing file only
  # warns; it does not fail the rebuild — which is exactly what makes the
  # lockout in secrets/README.md possible, so read that before repointing it.
  users.users.sebastianstupak = {
    isNormalUser = true;
    description = "Sebastian Stupak";
    shell = pkgs.zsh;
    hashedPasswordFile = config.sops.secrets.sebastianstupak-hash.path;
    extraGroups = [
      "wheel" # sudo
      "networkmanager"
      "video" # backlight control
      "audio"

      # podman, not docker. mutableUsers = false means an undeclared group
      # here is an activation failure, so this had to move in the same commit
      # that disabled docker. It grants the ROOTFUL socket; the rootless one
      # this user's test suites actually use needs no group at all.
      "podman"

      # Sunshine's virtual mouse and keyboard (modules/nixos/remote.nix).
      # Without it the stream is read-only: you see the desktop and cannot
      # click anything, which looks like a broken client rather than a missing
      # group. The group itself comes from hardware.uinput.enable, which the
      # Sunshine module turns on for us.
      "uinput"
    ];

    # Containers outlive the login session. Without lingering the user's
    # systemd session ends at logout and takes every running container with
    # it, including a database left up on purpose.
    linger = true;
  };

  # Calendar feed URLs, decrypted at activation for the user's vdirsyncer timer.
  # Replace the placeholders with the real links via:
  # sops secrets/common/calendars.yaml
  #
  # Declared HERE rather than in modules/home/calendar.nix because `sops.secrets`
  # is a NixOS option and that file is a home-manager module.
  #
  # `owner` is the load-bearing part. sops-nix writes secrets root-owned 0400 by
  # default, and vdirsyncer runs as a USER unit that reads the file with `cat` —
  # so without this it would get EPERM and fail in exactly the same way a missing
  # file does, which is a genuinely confusing thing to debug twice.
  #
  # Explicit `key`, so the /run/secrets name can be self-describing while the
  # YAML key stays short.
  #
  # These are shared, so they live under secrets/common/ and are encrypted to
  # every machine. The password hash is not — see each host.
  sops.secrets = {
    calendar-work-url = {
      sopsFile = ../../secrets/common/calendars.yaml;
      key = "work-url";
      owner = "sebastianstupak";
    };
    calendar-personal-url = {
      sopsFile = ../../secrets/common/calendars.yaml;
      key = "personal-url";
      owner = "sebastianstupak";
    };
  };

  # home-manager runs as a NixOS module: one `nixos-rebuild switch` manages the
  # whole machine, with a single generation list and unified rollback.
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs; };
    users.sebastianstupak = import ../../home/sebastianstupak;

    # Rename, don't abort. When home-manager starts managing a path that already
    # holds a real file — because an app wrote it imperatively before the config
    # declared it — activation refuses to clobber it and the whole switch fails.
    # That is the right default for a tool that never destroys data, but the
    # failure is mid-activation, so you get a half-applied generation and a
    # manual `mv` before you can retry.
    #
    # Hit first by xdg.mimeApps taking over ~/.config/mimeapps.list, which
    # Proton Mail and Claude Code had each registered a URL scheme in (see
    # modules/home/browsers.nix). It will happen again for any dotfile an app
    # owns before we do, so set it once here rather than per-file.
    #
    # Caveat: the backup is single-slot. If <path>.hm-bak already exists,
    # activation fails again with "backup file already exists" — clear the stale
    # .hm-bak rather than changing this extension, or the next collision just
    # moves the problem to a new suffix.
    backupFileExtension = "hm-bak";
  };

  # The NixOS release this system was first installed with.
  # Read the docs before ever changing this — do NOT bump it on upgrades.
  system.stateVersion = "26.05";
}
