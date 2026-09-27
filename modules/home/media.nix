# Media apps for consuming, not creating. Notation lives in music.nix.
# Spotify is unfree (allowUnfree is set in modules/nixos/core.nix).
# playerctl lets the Hyprland media keys control Spotify/browsers via MPRIS.
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    spotify
    playerctl
    mpv # video player
    vlc # media player
    imv # image viewer (Wayland)
    obs-studio # screen recording / streaming
  ];
}
