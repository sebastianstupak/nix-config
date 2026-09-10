# AGENTS.md

Guidance for AI agents (and humans) working in this repository. This is a
**flake-based NixOS configuration** for a single laptop daily-driver
(host `workstation`, user `sebastianstupak`). Keep changes small, formatted, and
committed. Follow the rules below exactly.

## Commands

All commands run from the repo root. `<host>` is `workstation`.

```bash
# Apply config: build + activate + set as boot default (needs root)
sudo nixos-rebuild switch --flake .#workstation

# Stage for next boot only — safer for risky changes (kernel, bootloader, FS)
sudo nixos-rebuild boot --flake .#workstation

# Build WITHOUT activating — the dry test to run after editing
nixos-rebuild build --flake .#workstation

# Verbose errors when evaluation fails
sudo nixos-rebuild switch --flake .#workstation --show-trace

# Validate the flake (eval + checks, incl. formatting). Run before committing.
nix flake check

# Format the whole tree (nixfmt-rfc-style, via treefmt)
nix fmt

# Dev shell: linters, formatter, lefthook, sops. Auto-loads via .envrc + direnv.
nix develop
deadnix .              # report dead/unused Nix code
statix check           # lint Nix antipatterns
lefthook run pre-commit   # run the git hooks manually (uses staged files)

# Update dependencies — do this in ITS OWN commit (see below)
nix flake update            # all inputs
nix flake update nixpkgs    # a single input
```

Rollback (independent of git): `sudo nixos-rebuild switch --rollback`, or pick an
older generation in the boot menu. Git versions the *source*; NixOS generations
version the *running system* — use both.

## Non-negotiable rules

1. **`git add` new files before rebuilding.** In a flake repo, Nix only sees
   files in the git working tree. A new `.nix` file you haven't staged **does not
   exist** to `nixos-rebuild` (you'll get "path does not exist" / "does not
   contain a flake.nix"). Run `git add -A` (or `--intent-to-add`) first.
2. **Never `.gitignore` `*.nix`, `flake.lock`, or `hardware-configuration.nix`.**
   Ignored ⇒ invisible to evaluation. `.gitignore` stays minimal on purpose.
3. **Always commit `flake.lock`.** It pins every input and is the entire
   reproducibility guarantee.
4. **Dependency bumps go in their own commit.** Never mix a `nix flake update`
   with a config change — a broken upgrade must stay bisectable/revertable.
5. **Secrets: never commit plaintext.** Only encrypted files under `secrets/` are
   committed; edit them via `sops`. See `secrets/README.md`.
6. **Do not run `nixos-rebuild switch` unprompted.** Propose the change and let
   the human apply it. `nixos-rebuild build` for verification is fine.
7. **`hardware-configuration.nix` is currently a placeholder.** It is regenerated
   on the real machine with `sudo nixos-generate-config --show-hardware-config`,
   then committed. Do not "fix" it to boot — that happens on the laptop.

## Project structure

```
flake.nix                     Entry point: inputs + nixosConfigurations + fmt/checks
flake.lock                    Pinned inputs (committed)
treefmt.nix                   nixfmt-rfc-style config for `nix fmt`
lefthook.yml                  pre-commit/pre-push linters (nixfmt/deadnix/statix, flake check)
statix.toml                   statix lint config (ignores generated hardware configs)
.githooks/                    committed git hooks (commit-msg, pre-commit, pre-push)
scripts/                      helper scripts (commit-msg.sh: Conventional Commits check)
.sops.yaml                    sops recipients + creation rules
hosts/<host>/
  default.nix                 Per-machine config; imports the profiles it needs + home-manager
  hardware-configuration.nix  Machine-specific; regenerated on the host, committed
modules/nixos/                System modules — core (baseline, always imported via default.nix)
                              + opt-in profiles: desktop (Hyprland), stylix (theming),
                              laptop (power/bt/fw), containers (docker)
modules/home/                 home-manager modules: shell, cli, terminal, editor,
                              browsers, git, dev, hyprland
home/<user>/                  Per-user home-manager config (identity)
secrets/                      Encrypted secrets only (sops-nix)
```

`flake.nix` exposes a `mkHost` helper that wires home-manager + sops-nix + stylix
once; `modules/nixos/default.nix` is the baseline (core only), and each host opts
into desktop/laptop/containers/stylix by importing them. This keeps a future
headless host from pulling in a desktop stack.

Add these directories only when you actually need them (YAGNI): `overlays/`
(nixpkgs overlays), `pkgs/` (custom `callPackage` packages), `lib/` (helper
functions). Document new top-level dirs here.

**Adding a host:** create `hosts/<name>/` importing the profiles it needs, then
add `<name> = mkHost ./hosts/<name>;` under `nixosConfigurations` in `flake.nix`.
**Adding a user:** create `home/<name>/` and reference it from the host's
`home-manager.users.<name>`.

## Code style

- Format with `nix fmt` (nixfmt-rfc-style) before every commit; `nix flake check`
  enforces it.
- Prefer explicit `pkgs.<name>` references. `with pkgs;` is acceptable **only**
  tightly scoped around a package list (e.g. `environment.systemPackages`), never
  around module logic.
- Comment *why*, not *what*: hardware quirks, workarounds, why an input is pinned.
  One header comment per module stating its purpose.
- Keep modules small and single-purpose. If a file sprawls, split it.
- `deadnix .` and `statix check` should be clean before committing (the hooks
  enforce this on NixOS).

## Linting & git hooks

Hooks are **committed** in `.githooks/` and activated with a repo-local
`core.hooksPath` (so they run identically on Windows and NixOS, independent of any
global git-hook setup). The Nix tools come from the dev shell (`flake.nix` →
`devShells.default`).

- **Wire them up (once, per checkout):** `direnv allow` (nix-direnv, via `.envrc`)
  or `nix develop` — the dev shell's `shellHook` runs `git config core.hooksPath
  .githooks`. Off-Nix (e.g. Windows) run that one command manually.
- **commit-msg:** rejects AI co-author trailers, then enforces Conventional
  Commits via `scripts/commit-msg.sh` (pure bash — always runs). See below.
- **pre-commit** → lefthook: `nixfmt` (formats staged `*.nix`, restages),
  `deadnix --fail`, `statix check`. **pre-push** → lefthook: `nix flake check`.
- Each lefthook job is **guarded** — it no-ops (exit 0) when its tool isn't on
  PATH (e.g. a Windows checkout without Nix), so hooks never block a commit
  off-NixOS. When the tool is present, its real failure blocks the commit/push.
- **Editing `lefthook.yml`:** keep every `run:` a single line with **no embedded
  quotes** — lefthook's Windows arg-parser mangles quoted/multiline commands.
- **Bypass once:** `git commit --no-verify` (or `LEFTHOOK=0` to skip only lefthook).

## Commit & PR conventions

Commit messages follow **Conventional Commits** (enforced by the commit-msg hook):

```
<type>(<optional-scope>)<optional-!>: <description>
```

- **types:** `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`,
  `ci`, `chore`, `revert`. `!` marks a breaking change. Subject ≤ 72 chars.
- **scope** is optional; use the area touched — e.g. `(home)`, `(workstation)`,
  `(modules/nixos)`, `(secrets)`, `(flake)`.
- Examples: `feat(home): add zsh with starship prompt` ·
  `fix(workstation): correct EFI mount point` · `chore: nix flake update`.
- Small, atomic commits; one logical change each. Commit **before** you `switch`
  so a good generation maps to a known commit.
- Lockfile bumps are standalone commits (rule 4) — e.g. `chore: nix flake update`.
- Solo workflow: a branch + `nixos-rebuild build` + `nix flake check`, then merge
  to `main`, is encouraged for anything risky.

## Verifying a change

Agents cannot boot this machine. To verify without applying:

```bash
nix flake check                              # eval + formatting
nixos-rebuild build --flake .#workstation    # full build, no activation
```

Report the actual output. If a build fails, include the error (add `--show-trace`)
— don't claim success without evidence.
