# Backups

restic to Scaleway Object Storage, from `modules/nixos/backup.nix`. Inert until
`my.backup.repository` is set; it is set for `workstation` in its host file.

```
repository   s3:https://s3.fr-par.scw.cloud/sstupak-restic-backups
schedule     daily, Persistent, up to 1h random delay
retention    7 daily, 5 weekly, 12 monthly — per machine
```

## The one thing to do before you need it

**Practise a restore.** An unverified backup is a guess. Do it once, now, while
nothing is wrong:

```bash
sudo restic -r s3:https://s3.fr-par.scw.cloud/sstupak-restic-backups snapshots
sudo restic -r … restore latest --target /tmp/restore-test --include /home/sebastianstupak/.ssh
ls /tmp/restore-test
```

The password comes from `/run/secrets/restic-password` and the credentials from
`/run/secrets/restic-env`; both are root-only, which is why these run under
`sudo`. To avoid retyping the repository every time:

```bash
export RESTIC_REPOSITORY=s3:https://s3.fr-par.scw.cloud/sstupak-restic-backups
export RESTIC_PASSWORD_FILE=/run/secrets/restic-password
set -a; . /run/secrets/restic-env; set +a
```

## Several machines, one repository

Every machine backs up to the **same** repository. restic is content-addressed,
so the licensed artifacts under `~/proprietary` and the dotfiles that are
identical on four laptops are stored once, not four times.

Snapshots carry the hostname, and `forget` runs with `--group-by host,paths`, so
"keep 7 daily" means seven *per machine*. One machine going quiet for a month
does not age out another's history.

**Exactly one host prunes.** `prune` takes an exclusive lock on the repository;
several machines pruning daily would collide and the losers would fail their
timers — a red indicator every morning that means nothing. `workstation` owns
it via `my.backup.prune = true`. Every other host leaves it off, which is the
default, so adding a machine is safe by construction.

Adding a machine: import the module, set the same `repository`, leave `prune`
alone, and give it the same two secrets. Nothing else.

## What is backed up

`/home/sebastianstupak`, minus things that are derived rather than authored:
caches, `node_modules`, `target`, `.venv`, `result` symlinks, VM images, and
the Ableton wineprefix.

That last one is the interesting line. The prefix is ~6 GB and entirely
regenerable by `ableton-install` from the zip in `~/proprietary` — so the
licensed artifacts are backed up and everything derived from them is not.
Plugins are installed into the slice and symlinked into the prefix precisely so
they land on the backed-up side of it. See [ABLETON.md](./ABLETON.md).

Roughly 34 GB today, of which 24 GB is one directory of e-reader dumps under
`dev/personal/boox/backups`. Those are a backup of a device you still own; they
are included deliberately, and they are most of the bill.

## What it does not protect against

It is a copy, not a snapshot. It runs daily, so anything created and destroyed
between runs was never backed up, and a file corrupted in place is faithfully
backed up corrupted. Retention is what gives you a corrupted-file escape hatch:
yesterday's snapshot still has the good version, for seven days.

## The passphrase

There is no reset. restic encrypts client-side; Scaleway stores ciphertext and
could not help if it wanted to. **The passphrase must exist somewhere that is
not this laptop** — Proton Pass — or a dead laptop takes every snapshot with it.

The same is true on a new machine: the passphrase and the API credentials are
the two things a rebuild cannot reproduce.

## The key expires

Scaleway caps API keys in this organization at one year, with no "never"
option. The current key expires **27 September 2027**, after which backups
start failing.

They will fail *loudly*: the service is ordered after `network-online.target`
and does not use a skip-if-offline condition, so a failure lights up the
`systemd-failed-units` indicator in the bar rather than passing unnoticed. That
is deliberate — a calendar sync that silently skips is nothing, a backup that
silently skips is the entire failure mode backups exist to prevent.

Rotating: generate a new key on the `restic-backup` application, then
`sops set secrets/backup.yaml '["restic-env"]' --value-stdin`.

## Where it lives, and why there

A Scaleway organization of its own (`sebastianstupak`), not the company one.
Scaleway allows one Organization per Owner account, so this is a separate
account on a separate address.

The key is an IAM application scoped to **one project** with object
read/write/delete and bucket *read* — it cannot delete the bucket, and it
cannot see anything else. The company organization's `Editors` policy grants
`AllProductsFullAccess` on **All Projects**, which is a wildcard that captures
projects created after the policy: any future employee would have reached a
backup bucket living there. Hence the separate account rather than a separate
project.

## Cost

Free until **26 December 2026** (750 GB trial). After that, Standard Multi-AZ
at €0.01606/GB/month — about €0.55/month for 34 GB, and roughly €1/month once
several machines are in. Ingress and requests are free; egress has a 75 GB
monthly free allowance, which is more than a full restore.
