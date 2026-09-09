# nix-config

Personal [NixOS](https://nixos.org) configuration — flake-based, [home-manager](https://github.com/nix-community/home-manager)
as a NixOS module, secrets via [sops-nix](https://github.com/Mic92/sops-nix).

- **Host:** `workstation` (HP laptop, daily driver)
- **User:** `sebastianstupak`
- **Channel:** `nixos-26.05`

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

## Layout

| Path | Purpose |
|------|---------|
| `flake.nix` | Inputs and `nixosConfigurations` |
| `hosts/<host>/` | Per-machine system config + hardware config |
| `modules/nixos/` | Reusable system modules |
| `modules/home/` | Reusable home-manager modules |
| `home/<user>/` | Per-user home-manager config |
| `secrets/` | Encrypted secrets (see [`secrets/README.md`](./secrets/README.md)) |

See **[AGENTS.md](./AGENTS.md)** for the full conventions, rules, and the
important git-and-flakes gotchas.
