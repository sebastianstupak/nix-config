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
    ../../modules/nixos/containers.nix # rootless podman
    ../../modules/nixos/netbird.nix # mesh VPN
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
  };

  # The NixOS release this system was first installed with.
  # Read the docs before ever changing this — do NOT bump it on upgrades.
  system.stateVersion = "26.05";
}
