# System-wide theming via Stylix. One base16 scheme (Kanagawa Dragon) colors
# GTK/Qt, ghostty, waybar, hyprland, hyprlock, neovim, etc. Because home-manager
# runs as a NixOS module here, Stylix applies to the user environment automatically.
{ config, pkgs, ... }:
{
  stylix = {
    enable = true;
    polarity = "dark";

    # Fixed palette from the Kanagawa Dragon base16 scheme (ships in
    # base16-schemes), rather than auto-deriving colors from the wallpaper.
    # Dragon is the desaturated, warmer sibling of stock Kanagawa: near-black
    # #181616 background, ash/clay accents instead of Kanagawa's blues.
    base16Scheme = "${pkgs.base16-schemes}/share/themes/kanagawa-dragon.yaml";

    # Placeholder wallpaper: a solid fill in the scheme's own background color so
    # the desktop matches out of the box. Derived from base00 rather than
    # hardcoded, so it can't drift out of sync when the scheme changes.
    # Drop a real image here later (e.g. ./wallpaper.png) — colors stay fixed by
    # base16Scheme regardless.
    image = pkgs.runCommand "wallpaper.png" { } ''
      ${pkgs.imagemagick}/bin/magick -size 3840x2160 \
        xc:'#${config.lib.stylix.colors.base00}' $out
    '';

    # Pointer cursor. Stylix installs the package and wires XCURSOR_THEME/size
    # plus the GTK/Qt settings. Bibata-Modern-Ice is a crisp white cursor —
    # stays legible against Dragon's near-black background.
    # Alternatives (drop-in, swap both lines):
    #   pkgs.bibata-cursors    "Bibata-Modern-Amber"    warm amber, leans into Dragon's palette
    #   pkgs.phinger-cursors   "phinger-cursors-light"  softer, rounder, slightly larger
    cursor = {
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Ice";
      size = 24;
    };

    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font";
      };
      sansSerif = {
        package = pkgs.noto-fonts;
        name = "Noto Sans";
      };
      serif = {
        package = pkgs.noto-fonts;
        name = "Noto Serif";
      };
      emoji = {
        package = pkgs.noto-fonts-color-emoji;
        name = "Noto Color Emoji";
      };
    };
  };
}
