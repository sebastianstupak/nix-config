# Secrets (sops-nix)

Encrypted secrets live here. **Only ciphertext is committed** — sops-nix decrypts
at activation time into `/run/secrets/<name>` (root-readable, or as configured).
Cloning this repo yields nothing but encrypted blobs.

The plumbing is already wired (`sops-nix` input in `flake.nix`,
`sops.age.sshKeyPaths` in `modules/nixos/core.nix`, `.sops.yaml` at the repo
root). No secret is declared yet, so it's currently a no-op. To add your first one:

## 1. Register a recipient key

sops encrypts to an **age** recipient. Derive one from an SSH key:

```bash
# from your user key
nix run nixpkgs#ssh-to-age -- -i ~/.ssh/id_ed25519.pub
# or the host key (matches core.nix), after the machine is installed
nix run nixpkgs#ssh-to-age -- -i /etc/ssh/ssh_host_ed25519_key.pub
```

Paste the resulting `age1...` value into `.sops.yaml`, replacing the placeholder.

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
