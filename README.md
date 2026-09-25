# nix-config

Personal [NixOS](https://nixos.org) configuration — flake-based, [home-manager](https://github.com/nix-community/home-manager)
as a NixOS module, secrets via [sops-nix](https://github.com/Mic92/sops-nix).

- **Host:** `workstation` (HP laptop, daily driver)
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

## Docs

Workflows a human follows. Module comments explain why a line of Nix exists;
these explain what to do.

| Doc | For |
|-----|-----|
| [docs/INSTALL.md](./docs/INSTALL.md) | A fresh install: wipe → NixOS, partitioning, hardware config, first boot, secrets |
| [docs/ORGS.md](./docs/ORGS.md) | The org model: identities, assistant profiles, workspaces, sessions |
| [docs/ABLETON.md](./docs/ABLETON.md) | The opt-in Ableton Live slice: installing, plugins, what is reproducible and what is not |
| [docs/GAMING.md](./docs/GAMING.md) | The opt-in gaming slice: Steam/Proton, Lutris, and Minecraft via Prism Launcher |

## Day-to-day

```bash
sudo nixos-rebuild switch --flake .#workstation   # apply changes
nixos-rebuild build --flake .#workstation         # build without activating
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
| `modules/nixos/` | System modules: `core` (baseline) + opt-in `desktop`/`stylix`/`laptop`/`containers`/`audio`/`gaming`/`backup`/`netbird` |
| `modules/home/` | home-manager modules — shell/cli/terminal/editor, browsers, office, media, comms, git, dev, security, hyprland, waybar, notifications, calendar, and the org slice (`orgs`, `org`, `herdr`, `claude-code-profiles`) |
| `home/<user>/` | Per-user config: identity, calendars, orgs — the data, not the mechanism |
| `docs/` | Human workflows (see the table above) |
| `.githooks/` + `scripts/` | Committed git hooks + the Conventional Commits check |
| `lefthook.yml` | pre-commit / pre-push linters (see [AGENTS.md](./AGENTS.md)) |
| `secrets/` | Encrypted secrets (see [`secrets/README.md`](./secrets/README.md)) |

Own options live under `my.*` and are declared by the module that owns them —
`my.orgs`, `my.calendars`, `my.claude.profiles`, `my.ableton.enable`,
`my.gaming.enable`, `my.backup.*`. The values are set in `home/<user>/` or
`hosts/<host>/`, keeping modules about mechanism and those files about this
person and this machine.

See **[AGENTS.md](./AGENTS.md)** for the full conventions, rules, and the
important git-and-flakes gotchas.
