# nix-config

Personal [NixOS](https://nixos.org) configuration — flake-based, [home-manager](https://github.com/nix-community/home-manager)
as a NixOS module, secrets via [sops-nix](https://github.com/Mic92/sops-nix).

- **Host:** `workstation` (HP laptop, daily driver)
- **User:** `sebastianstupak`
- **Channel:** `nixos-26.05`
- **Desktop:** Hyprland (Wayland) · greetd + tuigreet
- **Theme:** [Stylix](https://github.com/nix-community/stylix) with the Kanagawa scheme
- **Terminal / shell / editor:** ghostty · zsh + starship · neovim + Zed

> Working with an AI agent (or want the conventions)? Read **[AGENTS.md](./AGENTS.md)**.

## First-time setup (on the laptop)

1. Install NixOS and clone this repo:
   ```bash
   git clone https://github.com/sebastianstupak/nix-config.git ~/nix-config
   cd ~/nix-config
   ```
2. Generate this machine's hardware config (replaces the committed placeholder):
   ```bash
   sudo nixos-generate-config --show-hardware-config \
     > hosts/workstation/hardware-configuration.nix
   git add hosts/workstation/hardware-configuration.nix
   ```
3. Pick a desktop environment in `modules/nixos/desktop.nix` (uncomment a block).
4. Build and switch:
   ```bash
   sudo nixos-rebuild switch --flake .#workstation
   ```

## Day-to-day

```bash
sudo nixos-rebuild switch --flake .#workstation   # apply changes
nix fmt                                            # format before committing
nix flake check                                    # validate
nix flake update                                   # update inputs (own commit!)
sudo nixos-rebuild switch --rollback               # undo a bad switch
```

### Dev shell & git hooks

`direnv allow` (or `nix develop`) loads the linters, formatter, `lefthook`, and
`sops`, and activates the committed hooks (`git config core.hooksPath .githooks`):

- **commit-msg** — Conventional Commits (runs everywhere; see below).
- **pre-commit** — nixfmt / deadnix / statix on staged `*.nix`.
- **pre-push** — `nix flake check`.

The Nix linters no-op where Nix isn't installed, so a Windows checkout is never
blocked; the commit-msg check runs everywhere. Bypass once with
`git commit --no-verify`.

Commit messages follow **Conventional Commits** — `type(scope): description`
(types: `feat`, `fix`, `docs`, `refactor`, `chore`, `ci`, …). E.g.
`feat(home): add zsh with starship prompt`.

## Layout

| Path | Purpose |
|------|---------|
| `flake.nix` | Inputs and `nixosConfigurations` (via the `mkHost` helper) |
| `hosts/<host>/` | Per-machine config: imports the profiles it needs + hardware config |
| `modules/nixos/` | System modules: `core` (baseline) + opt-in `desktop`/`stylix`/`laptop`/`containers` |
| `modules/home/` | home-manager modules: shell, cli, terminal, editor, browsers, git, dev, hyprland |
| `home/<user>/` | Per-user home-manager config (identity) |
| `.githooks/` + `scripts/` | Committed git hooks + the Conventional Commits check |
| `lefthook.yml` | pre-commit / pre-push linters (see [AGENTS.md](./AGENTS.md)) |
| `secrets/` | Encrypted secrets (see [`secrets/README.md`](./secrets/README.md)) |

See **[AGENTS.md](./AGENTS.md)** for the full conventions, rules, and the
important git-and-flakes gotchas.
