# Gaming: Steam with Proton, performance tooling, and a Minecraft launcher.
#
# An opt-in vertical slice, like modules/nixos/audio.nix — importing this file
# does nothing until `my.gaming.enable = true`. It pulls in a 32-bit graphics
# stack and a few hundred megabytes of runtime that a headless or work-only
# machine has no reason to carry.
#
# Setting up an account, picking a Proton build, and the Minecraft side:
# docs/GAMING.md.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.gaming;
in
{
  options.my.gaming.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    example = true;
    description = ''
      Steam (with Proton), Lutris, gamemode/MangoHud, and Prism Launcher for
      Minecraft.

      Off by default rather than always-on: the 32-bit graphics stack this
      needs is a second full set of Mesa drivers, and Steam itself is unfree.
      Neither belongs on a machine that is not actually used for this.
    '';
  };

  config = lib.mkIf cfg.enable {
    # Steam and almost every Proton title still ship 32-bit code, so the driver
    # stack has to exist in both word sizes. `hardware.graphics.enable` is set
    # in desktop.nix; this is the other half, and without it Steam starts and
    # then fails to render.
    hardware.graphics.enable32Bit = true;

    programs.steam = {
      enable = true;

      # Proton-GE alongside Valve's builds: it carries media codecs and
      # game-specific fixes that Valve cannot ship for licensing reasons, which
      # is what most "cutscenes are black" reports come down to. It appears as
      # an extra entry in a game's compatibility list rather than replacing
      # anything — nothing switches to it until you pick it.
      extraCompatPackages = [ pkgs.proton-ge-bin ];

      # Both of these open firewall ports, so both stay off. Turn one on
      # deliberately if you actually stream to another device or host a server;
      # a laptop on untrusted Wi-Fi should not be listening by default.
      remotePlay.openFirewall = false;
      dedicatedServer.openFirewall = false;
    };

    # udev rules for Steam Controller, Steam Deck and the common third-party
    # pads. Harmless without a controller attached — it is only rules.
    hardware.steam-hardware.enable = true;

    # Asks the CPU governor for performance while a game is running and puts it
    # back afterwards, rather than pinning the whole machine to a performance
    # profile. On a laptop that distinction is the battery.
    programs.gamemode.enable = true;

    environment.systemPackages = with pkgs; [
      # Minecraft. Open source, packaged here, and it carries JDK 8/17/21/25 in
      # its own closure, so every Minecraft version from the old ones to the
      # current release has the Java it expects without anything installed
      # system-wide. Handles mod loaders (Fabric/Forge/Quilt/NeoForge) and keeps
      # instances separate.
      prismlauncher

      # Non-Steam games: GOG installers, itch, old Windows titles, emulators.
      lutris

      # An on-screen overlay for frame times and temperatures — the thing you
      # need when a game feels wrong and you want to know whether it is the GPU,
      # the CPU or thermal throttling. Launch with `mangohud <game>`, or tick it
      # in Lutris.
      mangohud

      # Manages Proton-GE versions for Lutris and Heroic. Steam's builds come
      # from extraCompatPackages above; this is for everything outside Steam.
      protonup-qt
    ];
  };
}
