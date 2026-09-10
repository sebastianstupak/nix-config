# Backups of $HOME with restic.
#
# This file is the MECHANISM and does nothing until `my.backup.repository` is
# set — see the option's description for the one-time setup. That gate is
# deliberate: a backup module that silently does nothing is worse than one that
# is visibly switched off, and there is no sensible default destination to guess.
#
# Why restic: content-addressed dedup and encryption happen client-side, so the
# destination never sees plaintext and never needs to be trusted. That is what
# makes "push to somebody else's storage" acceptable at all.
#
# What this does NOT protect against: it is a copy, not a snapshot. It runs
# daily, so anything created and destroyed between runs was never backed up, and
# a file corrupted in place is faithfully backed up corrupted. Restoring is
# `restic restore latest --target /some/path` — practise it once before you need
# it, because an unverified backup is a guess.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.backup;
in
{
  options.my.backup = {
    repository = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "rclone:proton:backups/workstation";
      description = ''
        Restic repository to push to, or null to disable backups entirely.

        Setup, once:
        1. Put a long random passphrase in `secrets/backup.yaml` under
           `restic-password` (`sops secrets/backup.yaml`). Store a copy
           somewhere that is NOT this laptop — losing it means losing every
           snapshot, since restic encrypts client-side and Anthropic-style
           "reset my password" does not exist for a repository.
        2. Set this option. `rclone:<remote>:<path>` needs an rclone remote
           configured for the user this runs as (root, here); an sftp:// or
           s3:// URL needs no extra tooling.
      '';
    };

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "/home/sebastianstupak" ];
      description = "Directories to back up.";
    };
  };

  config = lib.mkIf (cfg.repository != null) {
    # Declared inside the mkIf on purpose: sops-nix fails activation when a
    # declared secret is missing from the file, so an unconditional declaration
    # would break every rebuild until the passphrase exists.
    sops.secrets.restic-password = {
      sopsFile = ../../secrets/backup.yaml;
      key = "restic-password";
    };

    services.restic.backups.home = {
      inherit (cfg) repository paths;
      passwordFile = config.sops.secrets.restic-password.path;

      # Creates the repository on first run rather than failing until someone
      # remembers to `restic init` by hand.
      initialize = true;

      # Excludes are the difference between a backup you keep and one you cancel
      # because it is too slow. Everything here is either reproducible from the
      # flake, a cache, or enormous — and none of it is your data.
      exclude = [
        "/home/*/.cache"
        "/home/*/.local/share/Trash"
        "/home/*/.local/state/nix" # user nix profiles; rebuilt from the flake
        "/home/*/.nix-profile"
        "/home/*/.direnv"
        "**/node_modules"
        "**/target" # rust
        "**/.venv"
        "**/result" # nix build symlinks -> /nix/store
        "**/*.qcow2" # VM images: huge, and churn on every boot
      ];

      timerConfig = {
        OnCalendar = "daily";
        # Catch up after the laptop was asleep at the scheduled time, which for a
        # laptop is most of the time — without this a daily timer on a machine
        # that suspends overnight simply never fires.
        Persistent = true;
        # Avoid every machine hammering the destination at exactly midnight.
        RandomizedDelaySec = "1h";
      };

      # Retention. Runs after each backup, so the repository does not grow
      # forever. Restic's forget is safe to interrupt; prune is what reclaims.
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 5"
        "--keep-monthly 12"
      ];
    };

    # `restic-home` for interactive use: listing snapshots and restoring needs the
    # same repository and password the service uses, and typing those by hand is
    # how you discover your backup does not work.
    environment.systemPackages = [ pkgs.restic ];
  };
}
