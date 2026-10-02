# Syncthing: continuous file sync between this machine and my own devices.
#
# This file is the MECHANISM and does nothing until `my.syncthing.enable` is
# set, matching modules/nixos/backup.nix — a sync daemon that silently is or
# is not running is worse than one that is visibly switched off.
#
# Why Syncthing rather than a cloud folder: it is peer-to-peer and end-to-end
# encrypted, so no provider holds the data or the credentials. There is no API
# key on the device to steal, and nothing to scope — pairing is mutual and
# per-device, and revoking a device is one click. For a tablet that is easy to
# lose, "no long-lived cloud credential lives here at all" is worth more than
# any amount of care about where a credential is stored.
#
# What it is NOT: a backup. Syncthing faithfully replicates deletions and
# corruption to every peer. Backups are restic → Scaleway (modules/nixos/
# backup.nix), and because the synced folder lives under $HOME it is picked up
# there automatically. Versioning below is a convenience for fat-finger
# recovery, not a substitute.
#
# Conflicts: two devices editing the same file between syncs produces a
# `.sync-conflict-*` copy rather than a merge. That matters for .mscz, which is
# a zip and cannot be merged by anything — the practical habit is to let one
# device finish syncing before editing on the other.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.syncthing;
in
{
  options.my.syncthing = {
    enable = lib.mkEnableOption "Syncthing peer-to-peer file sync";

    user = lib.mkOption {
      type = lib.types.str;
      default = "sebastianstupak";
      description = ''
        User to run as. Syncthing runs as a real user rather than a system
        account so that synced files are owned by me and land with sane
        permissions — a folder full of root-owned files is useless.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/sebastianstupak";
      description = "Base directory that synced folders are created under.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Open 22000/tcp+udp (sync) and 21027/udp (local discovery).

        Without these the daemon still works via Syncthing's public relays, but
        every transfer is bounced through a third party and is far slower. On a
        LAN you want the direct path.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.syncthing = {
      enable = true;
      inherit (cfg) user dataDir;
      configDir = "${cfg.dataDir}/.config/syncthing";

      # NixOS opens 22000/tcp+udp and 21027/udp itself; no hand-rolled
      # firewall rules needed.
      openDefaultPorts = cfg.openFirewall;

      # The web UI binds to loopback only. Syncthing's GUI has no auth by
      # default, and exposing an unauthenticated admin surface that can add
      # sync folders anywhere on the filesystem is not something to do on a
      # laptop that joins untrusted networks. Reach it at
      # http://127.0.0.1:8384, or over an SSH tunnel from elsewhere.
      guiAddress = "127.0.0.1:8384";

      # Declarative devices/folders are deliberately NOT set here. Pairing
      # needs the peer's device ID, which is generated on first run of the
      # peer, and writing IDs into the flake means a rebuild to add a device.
      # `overrideFolders`/`overrideDevices` default to true and would wipe
      # anything added through the UI, so they are turned off.
      overrideFolders = false;
      overrideDevices = false;
    };

    environment.systemPackages = [
      pkgs.syncthing

      # `st` — the three things actually needed day to day, without hunting
      # through the web UI. Pairing in particular needs this machine's device
      # ID, which is otherwise buried in Actions → Show ID.
      (pkgs.writeShellScriptBin "st" ''
        set -uo pipefail
        jq=${pkgs.jq}/bin/jq
        cli() {
          ${pkgs.syncthing}/bin/syncthing cli --home=${lib.escapeShellArg config.services.syncthing.configDir} "$@"
        }
        case "''${1:-status}" in
          id)
            cli show system | "$jq" -r .myID
            ;;
          status)
            # Only `show system` emits JSON; the `config ... list` subcommands
            # print plain keys, one per line, and names/paths are separate
            # `get` calls. Piping those through jq was the bug.
            echo "this device:"
            cli show system | "$jq" -r .myID | sed "s/^/  /"

            echo "devices:"
            devs=$(cli config devices list 2>/dev/null)
            if [ -z "$devs" ]; then
              echo "  (none)"
            else
              for d in $devs; do
                name=$(cli config devices "$d" name get 2>/dev/null)
                echo "  ''${name:-<unnamed>}  ''${d%%-*}…"
              done
            fi

            echo "folders:"
            folders=$(cli config folders list 2>/dev/null)
            if [ -z "$folders" ]; then
              echo "  (none shared yet)"
            else
              for f in $folders; do
                path=$(cli config folders "$f" path get 2>/dev/null)
                echo "  $f  ''${path:-?}"
              done
            fi
            ;;
          gui)
            ${pkgs.xdg-utils}/bin/xdg-open http://${config.services.syncthing.guiAddress}
            ;;
          log)
            journalctl -u syncthing -n "''${2:-50}" --no-pager
            ;;
          *)
            echo "usage: st [status|id|gui|log [n]]" >&2
            exit 1
            ;;
        esac
      '')
    ];
  };
}
