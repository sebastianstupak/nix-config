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

  # Example config — replace/extend with your own programs.
  programs.git = {
    enable = true;
    settings.user = {
      name = "sebastianstupak";
      email = "sebastian.stupak@pm.me";
    };
  };
}
