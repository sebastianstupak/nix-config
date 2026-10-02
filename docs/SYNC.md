# Syncthing

Continuous file sync between this machine and my own devices. Mechanism lives
in `modules/nixos/syncthing.nix`; it does nothing until `my.syncthing.enable`.

## The command

```bash
st                  # this device's ID, its peers, and the synced folders
st id               # just the ID — what the other device needs to pair
st gui              # open the web UI
st log [n]          # recent daemon output (default 50 lines)
```

## Why Syncthing and not a cloud folder

Peer-to-peer and end-to-end encrypted: no provider holds the data, and there is
**no long-lived credential to steal** from any device. Pairing is mutual and
per-device, so revoking a lost tablet is one click and touches nothing else.

That last point is the whole argument. The alternative considered was Proton
Drive via rclone, which would have meant putting full Proton account
credentials *and* a TOTP seed on a rooted tablet — the same account that holds
Mail, Calendar and Pass — to talk to a beta reverse-engineered API. Syncthing
needs none of that.

## Pairing a device

Both ends have to add each other; there is no one-sided invite.

1. `st id` here, and find the other device's ID in its own UI.
2. Add each device to the other under **Add Remote Device**.
3. Share a folder from one side; accept it on the other.
4. Confirm with `st` — the peer and folder should both be listed.

The web UI binds to `127.0.0.1:8384` only. Syncthing's GUI has no auth by
default and can add sync folders anywhere on the filesystem, which is not
something to expose on a laptop that joins untrusted networks. From elsewhere,
tunnel it:

```bash
ssh -L 8384:127.0.0.1:8384 workstation
```

## Firewall

`my.syncthing.openFirewall` (default on) opens 22000/tcp+udp for sync and
21027/udp for local discovery. Without them the daemon still works, but every
transfer is bounced through Syncthing's public relays and is far slower. On a
LAN you want the direct path.

## This is not a backup

Syncthing replicates **deletions and corruption** to every peer, promptly and
faithfully. Delete a file here and it is gone on the tablet too.

Backups are restic → object storage ([BACKUP.md](./BACKUP.md)). Synced folders
live under `$HOME`, so they are already in scope — no extra configuration, but
also no excuse for treating sync as redundancy.

## Conflicts

Two devices editing the same file between syncs produces a
`.sync-conflict-<date>-<device>` copy rather than a merge. Nothing is lost, but
nothing is merged either.

This matters for `.mscz` (MuseScore) specifically: it is a zip, so no tool can
merge two versions — you pick one. The practical habit is to let one device
finish syncing before editing on the other.

## Declarative config, deliberately not

`overrideFolders` and `overrideDevices` are set to `false`. They default to
`true`, which would wipe anything added through the web UI on every rebuild.

Devices and folders are not declared in the flake because pairing needs the
peer's device ID, which only exists after that peer's first run — so declaring
them would mean a rebuild to add a device, and a secret-ish identifier in a
public config. The daemon is declarative; what it syncs is not.
