# System configuration for host "workstation" (HP laptop, daily driver).
# Composes: this host's hardware + the shared NixOS modules + home-manager.
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
    ../../modules/nixos/containers.nix # docker
    ../../modules/nixos/netbird.nix # mesh VPN
    ../../modules/nixos/backup.nix # restic (inert until my.backup.repository is set)
    # TEMPORARILY DISABLED for a fast rebuild — re-enable once the desktop is up.
    # It pulls shibco/ableton-linux (patched Wine, big from-source build).
    # ../../modules/nixos/audio.nix # pro-audio + Ableton (shibco/ableton-linux)
  ];

  networking.hostName = "workstation";

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

  # Users are fully declarative: nothing here is created or changed with
  # `useradd`/`passwd`, and anything NOT declared is removed on activation.
  #
  # This is what makes hashedPasswordFile authoritative — update-users-groups.pl
  # applies a declarative hash to an EXISTING user only when mutableUsers is
  # false (`$sp_pwdp = ... if defined $u->{hashedPassword} && !$spec->{mutableUsers}`).
  # With it true the hash sat there inert, which is how it was staged safely.
  #
  # The consequence worth remembering: `passwd` no longer changes your password.
  # Rotating it means writing a new hash into secrets/passwords.yaml and
  # rebuilding — see the secrets note below.
  #
  # Checked before enabling, because this flag removes undeclared state: the
  # only normal user is sebastianstupak (the nixbld* accounts belong to the nix
  # daemon), every group it actually holds is declared below, `users` is its
  # declared primary group rather than a stray membership, and uid 1000 is
  # pinned in /var/lib/nixos/uid-map so the dynamic allocation cannot move and
  # orphan every file in $HOME.
  users.mutableUsers = false;

  # Primary user.
  #
  # The hash is the one already in /etc/shadow, copied across verbatim, and it
  # was verified against libxcrypt's crypt(3) — the same function shadow uses —
  # before mutableUsers was flipped. So enabling it changed no password.
  #
  # A missing file only warns; it does not fail the rebuild.
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
      "docker"
    ];
  };

  # Calendar feed URLs, decrypted at activation for the user's vdirsyncer timer.
  # Replace the placeholders with the real links via: sops secrets/calendars.yaml
  #
  # Declared HERE rather than in modules/home/calendar.nix because `sops.secrets`
  # is a NixOS option and that file is a home-manager module. The host is also the
  # honest owner of "which secrets exist on this machine".
  #
  # `owner` is the load-bearing part. sops-nix writes secrets root-owned 0400 by
  # default, and vdirsyncer runs as a USER unit that reads the file with `cat` —
  # so without this it would get EPERM and fail in exactly the same way a missing
  # file does, which is a genuinely confusing thing to debug twice.
  #
  # Explicit `key`, so the /run/secrets name can be self-describing while the
  # YAML key stays short.
  sops.secrets = {
    # Login password hash. Root-owned 0400 is correct here — unlike the calendar
    # URLs, the reader is update-users-groups.pl running as root, not a user unit.
    sebastianstupak-hash = {
      sopsFile = ../../secrets/passwords.yaml;
      key = "sebastianstupak-hash";
      # Available before users are set up, not just after activation.
      neededForUsers = true;
    };

    calendar-work-url = {
      sopsFile = ../../secrets/calendars.yaml;
      key = "work-url";
      owner = "sebastianstupak";
    };
    calendar-personal-url = {
      sopsFile = ../../secrets/calendars.yaml;
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
