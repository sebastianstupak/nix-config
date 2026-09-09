# home-manager configuration for user "sebastianstupak".
{ ... }:
{
  imports = [ ../../modules/home ];

  home.username = "sebastianstupak";
  home.homeDirectory = "/home/sebastianstupak";

  # The home-manager release this profile was created with. Keep in sync with the
  # host's system.stateVersion; do not bump it casually.
  home.stateVersion = "26.05";

  # Example config — replace/extend with your own programs.
  programs.git = {
    enable = true;
    userName = "sebastianstupak";
    userEmail = "sebastian.stupak@pm.me";
  };
}
