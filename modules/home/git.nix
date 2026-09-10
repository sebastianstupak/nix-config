# Shared git configuration. Per-user identity (name/email) is set in home/<user>/.
{ ... }:
{
  programs.git = {
    enable = true;
    settings = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      alias = {
        s = "status -sb";
        lg = "log --oneline --graph --decorate";
      };
    };
  };
}
