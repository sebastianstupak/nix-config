# System configuration for host "workstation" (HP laptop, daily driver).
# Composes: this host's hardware + the shared NixOS modules + home-manager.
{ inputs, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos # baseline (core)
    ../../modules/nixos/desktop.nix # Hyprland graphical session
    ../../modules/nixos/stylix.nix # system-wide theming (Kanagawa)
    ../../modules/nixos/laptop.nix # power, bluetooth, firmware, backlight
    ../../modules/nixos/containers.nix # docker
    ../../modules/nixos/netbird.nix # mesh VPN
    # TEMPORARILY DISABLED for a fast rebuild — re-enable once the desktop is up.
    # It pulls shibco/ableton-linux (patched Wine, big from-source build).
    # ../../modules/nixos/audio.nix # pro-audio + Ableton (shibco/ableton-linux)
  ];

  networking.hostName = "workstation";

  # Bootloader. systemd-boot assumes UEFI firmware — adjust if you use BIOS/GRUB.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Primary user. Set a password after first boot with `passwd`, or manage it via sops.
  users.users.sebastianstupak = {
    isNormalUser = true;
    description = "Sebastian Stupak";
    shell = pkgs.zsh;
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
