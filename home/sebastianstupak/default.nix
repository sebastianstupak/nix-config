# home-manager configuration for user "sebastianstupak".
{ ... }:
{
  imports = [ ../../modules/home ];

  home = {
    username = "sebastianstupak";
    homeDirectory = "/home/sebastianstupak";

    # The home-manager release this profile was created with. Keep in sync with
    # the host's system.stateVersion; do not bump it casually.
    stateVersion = "26.05";
  };

  # Per-user git identity (shared git config lives in modules/home/git.nix).
  programs.git.settings.user = {
    name = "sebastianstupak";
    email = "sebastian.stupak@pm.me";
  };
}
