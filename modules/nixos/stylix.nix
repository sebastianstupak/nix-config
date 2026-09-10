# System-wide theming via Stylix. One base16 scheme (Kanagawa) colors GTK/Qt,
# ghostty, waybar, hyprland, hyprlock, neovim, etc. Because home-manager runs as
# a NixOS module here, Stylix applies to the user environment automatically.
{ pkgs, ... }:
{
  stylix = {
    enable = true;
    polarity = "dark";

    # Fixed palette from the Kanagawa base16 scheme (ships in base16-schemes),
    # rather than auto-deriving colors from the wallpaper.
    base16Scheme = "${pkgs.base16-schemes}/share/themes/kanagawa.yaml";

    # Placeholder wallpaper: a solid fill in Kanagawa's "sumiInk" background so
    # the desktop matches the scheme out of the box. Drop a real image here later
    # (e.g. ./wallpaper.png) — colors stay fixed by base16Scheme regardless.
    image = pkgs.runCommand "wallpaper.png" { } ''
      ${pkgs.imagemagick}/bin/magick -size 3840x2160 xc:'#1f1f28' $out
    '';

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
