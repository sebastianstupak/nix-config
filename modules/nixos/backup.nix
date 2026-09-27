# Backups of $HOME with restic.
#
# Restoring, adding a machine, rotating the key, and what is deliberately not
# backed up: docs/BACKUP.md. Practise the restore before you need it.
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

    prune = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether THIS host applies the retention policy to the repository.

        Every machine here backs up to one shared repository, because restic
        deduplicates across the whole thing: the same licensed artifacts and the
        same dotfiles on four laptops are stored once, not four times. Snapshots
        carry the hostname, and `forget` groups by host, so each machine keeps
        its own history rather than aging out its siblings'.

        Pruning is the part that cannot be shared. It takes an EXCLUSIVE lock on
        the repository, so four machines pruning daily would collide and the
        losers would fail their timers — a red indicator every morning that
        means nothing. Exactly one host should own it.

        Off by default so that adding a machine is safe: a new host backs up and
        nothing else until you decide it should be the one that prunes.
      '';
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

    # Credentials for the destination, as KEY=VALUE lines that systemd loads as
    # the service's environment (B2_ACCOUNT_ID/B2_ACCOUNT_KEY for Backblaze,
    # AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY for S3). Separate from the
    # repository passphrase because they protect different things: this one
    # authorises writing to the bucket, that one decrypts the snapshots.
    #
    # An environment file rather than a repository URL with the key baked in —
    # a URL would land in the store and in `ps`. Harmless and unused for a local
    # or sftp repository; leave the value empty in that case.
    sops.secrets.restic-env = {
      sopsFile = ../../secrets/backup.yaml;
      key = "restic-env";
    };

    services.restic.backups.home = {
      inherit (cfg) repository paths;
      passwordFile = config.sops.secrets.restic-password.path;
      environmentFile = config.sops.secrets.restic-env.path;

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

        # The Ableton wineprefix: 14 GB, entirely regenerable by
        # `ableton-install` from the zip in ~/proprietary, and it churns — Live
        # writes analytics.db, crash logs and caches inside it, so restic would
        # push new blobs on every run forever.
        #
        # This exclusion is the reproducibility boundary, not just a size
        # tweak: ~/proprietary holds the licensed artifacts a new machine
        # actually needs and stays backed up, while everything derived from
        # them does not. Plugins live in the slice and are symlinked into the
        # prefix (see modules/nixos/audio.nix) precisely so that they fall on
        # the backed-up side of this line.
        "/home/*/.wine-ableton"
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

      # Retention, on the designated pruner only — see `my.backup.prune`.
      # Empty here means this host backs up and never expires anything, which is
      # what every machine except one should do against a shared repository.
      #
      # `--group-by host,paths` is restic's default and is written out anyway,
      # because the whole multi-machine design rests on it: it makes "keep 7
      # daily" mean seven per machine. Were it ever to become a flat global
      # policy, four machines would quietly evict each other's history and the
      # symptom would be a missing snapshot nobody thinks to look for.
      pruneOpts = lib.optionals cfg.prune [
        "--group-by host,paths"
        "--keep-daily 7"
        "--keep-weekly 5"
        "--keep-monthly 12"
      ];
    };

    # Wait for the network before running.
    #
    # The timer is Persistent, so on boot and resume it fires the run it missed
    # while the machine was off — and without this that lands before
    # NetworkManager has a connection. This is not hypothetical: the identical
    # race hit vdirsyncer twice (see the ExecCondition note in
    # modules/home/calendar.nix), both times within seconds of the machine
    # coming back.
    #
    # Ordering rather than calendar.nix's skip-if-offline condition, because the
    # two want opposite outcomes. A missed calendar sync is nothing; a backup
    # that silently does not run is the whole failure mode backups exist to
    # prevent, so this one should still fail loudly and light up the
    # failed-units indicator. network-online.target is real here because
    # NetworkManager-wait-online is enabled.
    systemd.services.restic-backups-home = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
    };

    # `restic` for interactive use: listing snapshots and restoring needs the
    # same repository and password the service uses, and typing those by hand is
    # how you discover your backup does not work.
    environment.systemPackages = [ pkgs.restic ];
  };
}
