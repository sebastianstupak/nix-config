# Shared git configuration. Per-user identity (name/email) is set in home/<user>/.
{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  # Every identity one key signs for: the global one plus each org that has
  # declared an address. Deduplicated, because an org may legitimately reuse it.
  emails = lib.unique (
    [ config.programs.git.settings.user.email ]
    ++ (lib.mapAttrsToList (_: org: org.email) (
      lib.filterAttrs (_: org: org.email != null) config.my.orgs
    ))
  );
in
{
  programs.git = {
    enable = true;

    # Commit signing with the SSH key rather than GPG. Same "Verified" badge on
    # GitHub, but no GPG keyring to manage, and the one key also serves pushes
    # and (via ssh-to-age) sops-nix.
    #
    # `key` is the PUBLIC key on purpose: with format=ssh, git hands it to
    # `ssh-keygen -Y sign`, which asks the agent to do the signing. That keeps
    # the passphrase-protected private key in the agent rather than being read —
    # and re-prompted for — on every commit. Load it once with
    # `ssh-add ~/.ssh/id_ed25519`; gpg-agent (services.gpg-agent.enableSshSupport
    # in security.nix) retains it afterwards.
    signing = {
      format = "ssh";
      key = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
      signByDefault = true;
    };

    settings = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;

      # Lets `git log --show-signature` verify our own commits locally. Without
      # it git still creates signatures, but reports every one as untrusted.
      # Generated at activation (see home.activation.gitAllowedSigners below)
      # because it has to embed the public key's actual contents.
      gpg.ssh.allowedSignersFile = "${config.xdg.configHome}/git/allowed_signers";

      # Push to GitHub over HTTPS without a prompt, reusing the token `gh auth
      # login` already stored. This is what `gh auth setup-git` writes into
      # ~/.gitconfig imperatively — declared here instead so it survives a
      # rebuild. Absolute store path rather than bare `gh`, because git runs
      # credential helpers through a plain shell that need not have the user
      # profile on PATH.
      credential."https://github.com".helper = "!${pkgs.gh}/bin/gh auth git-credential";

      # Same idea for the self-hosted Forgejo, but there is no `gh` for it and
      # SSH is disabled on the instance, so HTTPS + a stored PAT is the only
      # way in. `git-credential-netrc` ships inside git itself; the netrc it
      # reads is rendered from sops (hosts/common/default.nix sops.templates).
      #
      # WITHOUT THIS, EVERY FETCH AND PUSH OPENS A GUI PASSWORD PROMPT. The
      # fall-through is not a terminal prompt but SSH_ASKPASS — set to
      # ssh-askpass-pinentry by security.nix, with SSH_ASKPASS_REQUIRE=prefer —
      # so git asks pinentry for a username and password on every single remote
      # operation, and `GIT_TERMINAL_PROMPT=0` does NOT suppress it (that only
      # governs the terminal path). A script that pushes therefore hangs on a
      # dialog instead of failing, which is the worse of the two outcomes.
      #
      # Absolute store path, as with `gh` above: credential helpers run under a
      # plain shell that need not have the user profile on PATH.
      credential."https://git.datadir.dev".helper = "!${pkgs.git}/bin/git-credential-netrc -f ${
        osConfig.sops.templates."forgejo-netrc".path
      }";

      alias = {
        s = "status -sb";
        lg = "log --oneline --graph --decorate";
      };
    };
  };

  # Per-org commit identity, keyed on where the repo lives.
  #
  # Without this every commit in every repo is authored by the global address,
  # which on this machine meant work repos signed as a personal identity. The
  # boundary is the DIRECTORY rather than a mode you switch into, because the
  # failure of mode-switching is always the same: you forget which mode you are
  # in and only find out after pushing.
  #
  # Only orgs that declare an email get an override; the rest fall through to
  # the global identity. That way an org can be listed before its address is
  # known without silently attributing commits to the wrong person.
  programs.git.includes = lib.mapAttrsToList (_: org: {
    condition = "gitdir:${org.directory}/";
    contents.user = {
      inherit (org) email;
      inherit (config.programs.git.settings.user) name;
    };
  }) (lib.filterAttrs (_: org: org.email != null) config.my.orgs);

  # allowed_signers maps an identity to the key trusted to sign for it, in the
  # form "<email> <keytype> <keydata>". Written at activation rather than as a
  # home.file because it needs the public key's contents, which live outside the
  # store — and committing the key material here just to generate it would tie
  # the repo to one machine's key.
  #
  # Every org address needs its own line. One key signs for all of them, but
  # verification is per-identity: an org email missing here makes git report its
  # own commits as signed by an unknown signer.
  home.activation.gitAllowedSigners = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    key="$HOME/.ssh/id_ed25519.pub"
    dest="${config.xdg.configHome}/git/allowed_signers"
    if [ -r "$key" ]; then
      mkdir -p "$(dirname "$dest")"
      : > "$dest"
      ${lib.concatMapStringsSep "\n" (email: ''
        printf '%s %s\n' ${lib.escapeShellArg email} "$(cat "$key")" >> "$dest"
      '') emails}
    fi
  '';
}
