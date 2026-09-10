# Media apps. Spotify is unfree (allowUnfree is set in modules/nixos/core.nix).
# playerctl lets the Hyprland media keys control Spotify/browsers via MPRIS.
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    spotify
    playerctl
    mpv # video player
    imv # image viewer (Wayland)
    obs-studio # screen recording / streaming
  ];
}
