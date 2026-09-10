# Shared git configuration. Per-user identity (name/email) is set in home/<user>/.
{ pkgs, ... }:
{
  programs.git = {
    enable = true;
    settings = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;

      # Push to GitHub over HTTPS without a prompt, reusing the token `gh auth
      # login` already stored. This is what `gh auth setup-git` writes into
      # ~/.gitconfig imperatively — declared here instead so it survives a
      # rebuild. Absolute store path rather than bare `gh`, because git runs
      # credential helpers through a plain shell that need not have the user
      # profile on PATH.
      credential."https://github.com".helper = "!${pkgs.gh}/bin/gh auth git-credential";
      alias = {
        s = "status -sb";
        lg = "log --oneline --graph --decorate";
      };
    };
  };
}
