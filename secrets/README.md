# Secrets (sops-nix)

Encrypted secrets live here. **Only ciphertext is committed** — sops-nix decrypts
at activation time into `/run/secrets/<name>` (root-readable, or as configured).
Cloning this repo yields nothing but encrypted blobs.

The plumbing is already wired (`sops-nix` input in `flake.nix`,
`sops.age.sshKeyPaths` in `modules/nixos/core.nix`, `.sops.yaml` at the repo
root). No secret is declared yet, so it's currently a no-op. To add your first one:

## 1. Recipient keys (already registered)

`.sops.yaml` encrypts every secret to **two** age recipients, and both are
needed:

| recipient | source | why |
| --- | --- | --- |
| `workstation` | host key `/etc/ssh/ssh_host_ed25519_key` | sops-nix decrypts as root at activation (`sops.age.sshKeyPaths`, `modules/nixos/core.nix`). Without it the machine cannot read its own secrets at boot. |
| `sebastianstupak` | standalone age key `~/.config/sops/age/keys.txt` | `sops` runs as you and cannot read the root-owned host key. Without it you could create a secret and never reopen it. |

The user recipient is a standalone age key rather than one derived from
`~/.ssh/id_ed25519`: that key is passphrase-protected, and `ssh-to-age` has no
passphrase support, so an ssh-derived recipient would encrypt to something
nothing can decrypt. sops cannot consume the ssh key as an age identity either.

`~/.config/sops/age/keys.txt` is **not** in this repo and is not reproducible —
it is machine-local secret material, mode 600. Back it up somewhere safe: lose
it and you can still decrypt via the host key with `sudo`, but lose both and
the secrets are gone. Regenerate a replacement with `age-keygen`, then update
`.sops.yaml` and run `sops updatekeys secrets/<file>`.

To re-derive the values:

```bash
nix run nixpkgs#ssh-to-age -- -i /etc/ssh/ssh_host_ed25519_key.pub  # host
grep 'public key' ~/.config/sops/age/keys.txt                       # user
```

## 2. Create an encrypted file

```bash
sops secrets/secrets.yaml
```

Your `$EDITOR` opens on decrypted content; sops re-encrypts on save. Add e.g.:

```yaml
example_token: super-secret-value
```

## 3. Declare the secret in Nix

In a module (or the host config):

```nix
sops.secrets."example_token" = {
  sopsFile = ../../secrets/secrets.yaml;
  # owner = "sebastianstupak"; mode = "0400"; etc.
};
```

Reference the decrypted path at runtime via
`config.sops.secrets."example_token".path` (→ `/run/secrets/example_token`).

## Rules

- **Never** commit plaintext. Only edit secret files through `sops`.
- `git add` the encrypted file before you rebuild (see the repo `AGENTS.md`).
- If you rotate/add recipients, run `sops updatekeys secrets/secrets.yaml`.
