# nix-config

Personal [NixOS](https://nixos.org) configuration — flake-based, [home-manager](https://github.com/nix-community/home-manager)
as a NixOS module, secrets via [sops-nix](https://github.com/Mic92/sops-nix).

- **Hosts:** `zagreus` (AMD HP laptop, daily driver) and `hestia` (HP ZBook
  Firefly 14 G10, Intel i7-1355U). One entry each, both importing
  `hosts/common/`; they still share the hand-merged hardware config. See
  [Two machines](#two-machines).
- **User:** `sebastianstupak`
- **Channel:** `nixos-26.05`
- **Desktop:** Hyprland (Wayland) · greetd + tuigreet · waybar
- **Theme:** [Stylix](https://github.com/nix-community/stylix) with the Kanagawa scheme
- **Terminal / shell / editor:** ghostty · zsh + starship · neovim + Zed

> Working with an AI agent (or want the conventions)? Read **[AGENTS.md](./AGENTS.md)**.

## Orgs

The one idea worth knowing before reading anything else. This machine is used
for several organisations, and **the boundary between them is a directory**:
anything under `~/dev/<org>/` belongs to that org, and every tool works it out
from the path rather than from a mode you have to remember to switch.

One entry in `my.orgs` gives an org its commit identity, its own assistant
account and MCP servers, a pair of named workspaces with their own glyph and
colour in the bar, and a terminal session that survives being closed.

```bash
org                 # pick an org (also $mod+O)
org datadir         # its home screen, with its terminal
org datadir 2       # its second screen
```

**[docs/ORGS.md](./docs/ORGS.md)** — how it fits together, adding an org, and
what a rebuild cannot reproduce on a new machine.

## Sync

Files follow me between this machine and my own devices — currently the Boox
Note Air 4C, which carries sheet music. Syncthing is peer-to-peer and
end-to-end encrypted, so no provider holds the data and there is no long-lived
cloud credential sitting on a tablet that is easy to lose.

```bash
st                  # this device's ID, its peers, and the synced folders
st id               # just the ID — what the other device needs to pair
st gui              # open the web UI (127.0.0.1:8384, loopback only)
st log [n]          # recent daemon output
```

`st id` is the one to reach for first: pairing needs this machine's device ID,
which is otherwise buried in the web UI under Actions → Show ID.

It is **not** a backup — Syncthing replicates deletions faithfully. Backups are
restic (see below); synced folders live under `$HOME`, so they are covered.

**[docs/SYNC.md](./docs/SYNC.md)** — pairing a new device, folder layout, and
the conflict behaviour that matters for binary files.

## Two machines

Two physical machines, **one host entry each**, both importing
`hosts/common/`. A host entry holds only what distinguishes the machine:

| | `zagreus` | `hestia` |
|---|---|---|
| machine | AMD HP laptop, daily driver | HP ZBook Firefly 14 G10, Intel i7-1355U |
| hostname | `zagreus` | `hestia` |
| restic | backs up **and prunes** | backs up, expires nothing |
| password secret | `secrets/common/passwords.yaml` | `secrets/common/passwords.yaml` |

They shared a single entry until the second machine needed its own hostname and
password. That is not a preference: one `nixosConfiguration` produces one
`networking.hostName` and one `hashedPasswordFile`, and Nix cannot branch on
which machine is evaluating it — so per-machine anything forces per-machine
hosts.

Splitting fixed a real bug on the way. `my.backup.prune` was set in the shared
entry, so **both** machines pruned the shared repository — and pruning takes an
exclusive lock, which the module's own comment says has to be exactly one of
them. It now lives on `zagreus` alone. Snapshot grouping was wrong for the
same reason: `forget --group-by host` groups by hostname, and both machines
answered to `workstation`, so each was ageing out the other's history. Those
old snapshots stay in the retired `workstation` group and are no longer covered
by either machine's retention — forget them by hand once the new groups look
right.

### Still shared, deliberately

`hosts/common/hardware-configuration.nix` is one hand-merged file for both
machines, because they differ in CPU vendor and storage controller:

| What | Why |
|------|-----|
| `by-label` mounts | UUIDs are per-filesystem and differ between the machines; labels are set identically at `mkfs` time (`-L nixos`, `-n BOOT`) |
| Union of initrd modules | `nvme`/`xhci_pci` on both, plus `thunderbolt`/`uas`/`sd_mod` for the Intel machine. Dropping one makes that machine fail to find its root device |
| Both AMD *and* Intel microcode | each option is inert on the CPU it doesn't match; leaving only AMD means the Intel machine silently gets no microcode updates |
| `systemd.services.load-kvm` | the right `kvm` module differs per CPU and can't be chosen at eval time. Naming both in `boot.kernelModules` would leave `systemd-modules-load` permanently failed on whichever machine doesn't match |

**Splitting this file is the obvious next step and is deliberately not done.**
Deriving one machine's half from the union is guesswork, and getting it wrong
leaves that machine unbootable. To do it properly, generate on each machine in
turn and compare against the union.

**The costs that remain:**

- **`hardware-configuration.nix` is hand-merged, not generated.** Running
  `nixos-generate-config --show-hardware-config` over it destroys the merge and
  leaves the *other* machine unbootable. The file says so at the top, and the
  `hardware-config-is-real` flake check fails on `by-uuid` for this reason.
- **Labels collide.** If both disks are ever in one machine, the initrd may pick
  the wrong root. Mount the other machine's disk by UUID explicitly.
- **The password is still shared.** Both hosts point at
  `secrets/common/passwords.yaml`. The per-host layout and `.sops.yaml` rules
  are in place; see "Splitting a host's password" in
  [`secrets/README.md`](./secrets/README.md) for the order that avoids the
  lockout.

### Secrets per machine

`.sops.yaml` encrypts by path:

```
secrets/common/      → both host keys + your age key   (restic creds must be readable by all)
secrets/zagreus/ → that host key + your age key
secrets/hestia/     → that host key + your age key
```

A host directory excludes the other machines on purpose: a stolen laptop can
read the hash it already had to have, and not the other's. The price is that
your standalone age key becomes the only way to re-key a reinstalled host from
elsewhere — so it has to live off-machine. See
[`secrets/README.md`](./secrets/README.md).

## Docs

Workflows a human follows. Module comments explain why a line of Nix exists;
these explain what to do.

| Doc | For |
|-----|-----|
| [docs/INSTALL.md](./docs/INSTALL.md) | A fresh install: wipe → NixOS, partitioning, hardware config, first boot, secrets |
| [docs/ORGS.md](./docs/ORGS.md) | The org model: identities, assistant profiles, workspaces, sessions |
| [docs/ABLETON.md](./docs/ABLETON.md) | The opt-in Ableton Live slice: installing, plugins, what is reproducible and what is not |
| [docs/GAMING.md](./docs/GAMING.md) | The opt-in gaming slice: Steam/Proton, Lutris, and Minecraft via Prism Launcher |
| [docs/BACKUP.md](./docs/BACKUP.md) | restic to object storage: what is backed up, restoring, and the several-machines design |
| [docs/MUSIC.md](./docs/MUSIC.md) | MuseScore and Muse Hub: sound libraries, the audio path, and two things that are not bugs |
| [docs/SYNC.md](./docs/SYNC.md) | Syncthing: pairing a device, the `st` command, and why this is not a backup |

## Day-to-day

```bash
sudo nixos-rebuild switch --flake .#zagreus   # apply changes
nixos-rebuild build --flake .#zagreus         # build without activating
nix fmt                                            # format before committing
nix flake check                                    # validate
nix flake update                                   # update inputs (own commit!)
sudo nixos-rebuild switch --rollback               # undo a bad switch
```

Git versions the *source*; NixOS generations version the *running system*. Use
both — a rollback does not need a working git tree.

### What `nix flake check` actually checks

More than evaluation. Each of these exists because the thing it guards fails
*silently* otherwise:

| Check | Catches |
|-------|---------|
| `formatting` | anything not formatted with nixfmt |
| `hyprland-config` | bad binds, unknown dispatchers, malformed workspace rules |
| `fuzzel-config` | unknown keys and malformed colours in the launcher |
| `waybar-config` / `waybar-style` | invalid bar config; CSS that GTK would skip rather than reject |
| `git-hook-policy` | the commit-message policy, driven through real `git commit` runs |
| `herdr-org-sessions` | the session wrapper rewriting arguments it should pass through |
| `org-terminal-class` | the terminal's app-id drifting from what the launcher matches on |
| `hardware-config-is-real` | a placeholder hardware config reaching a machine |

### Dev shell & git hooks

`direnv allow` (or `nix develop`) loads the linters, formatter, `lefthook`, and
`sops`, and activates the committed hooks (`git config core.hooksPath .githooks`):

- **commit-msg** — Conventional Commits, plus the AI-attribution policy below.
- **pre-commit** — nixfmt / deadnix / statix on staged `*.nix`.
- **pre-push** — `nix flake check`.

The Nix linters no-op where Nix isn't installed, so a Windows checkout is never
blocked; the commit-msg check runs everywhere. Bypass once with
`git commit --no-verify`.

Commit messages follow **Conventional Commits** — `type(scope): description`
(types: `feat`, `fix`, `docs`, `refactor`, `chore`, `ci`, …). E.g.
`feat(home): add zsh with starship prompt`.

Separately, a **machine-wide** hook (`modules/home/git-hooks.nix`) applies in
*every* repo on this machine: attribution trailers are stripped, and a message
naming an AI vendor or claiming to be AI-written is rejected rather than
rewritten. This repo overrides `core.hooksPath`, so `.githooks/commit-msg`
carries its own copy of that rule and a flake check keeps the two in step.

## Layout

| Path | Purpose |
|------|---------|
| `flake.nix` | Inputs, `nixosConfigurations` (via `mkHost`), and the checks above |
| `hosts/<host>/` | Per-machine config: imports the profiles it needs + hardware config |
| `modules/nixos/` | System modules: `core` (baseline) + opt-in `desktop`/`stylix`/`laptop`/`containers`/`audio`/`gaming`/`backup`/`netbird`/`syncthing` |
| `modules/home/` | home-manager modules — shell/cli/terminal/editor, browsers, office, media, music, comms, git, dev, security, hyprland, waybar, notifications, calendar, and the org slice (`orgs`, `org`, `herdr`, `claude-code-profiles`) |
| `home/<user>/` | Per-user config: identity, calendars, orgs — the data, not the mechanism |
| `docs/` | Human workflows (see the table above) |
| `.githooks/` + `scripts/` | Committed git hooks + the Conventional Commits check |
| `lefthook.yml` | pre-commit / pre-push linters (see [AGENTS.md](./AGENTS.md)) |
| `secrets/` | Encrypted secrets (see [`secrets/README.md`](./secrets/README.md)) |

Own options live under `my.*` and are declared by the module that owns them —
`my.orgs`, `my.calendars`, `my.claude.profiles`, `my.ableton.enable`,
`my.gaming.enable`, `my.backup.*`, `my.syncthing.*`. The values are set in `home/<user>/` or
`hosts/<host>/`, keeping modules about mechanism and those files about this
person and this machine.

See **[AGENTS.md](./AGENTS.md)** for the full conventions, rules, and the
important git-and-flakes gotchas.
