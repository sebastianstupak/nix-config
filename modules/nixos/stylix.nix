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
    #
    # bibata-cursors ships 12 variants totalling ~324 MiB; we use exactly one
    # (27 MiB). Copy just that variant out so the *system closure* references
    # only it — the full package stays a build-time input and is collectable.
    # To switch variant, change both the name below and the copied directory.
    # Alternatives: "Bibata-Modern-Amber" (warm, leans into Dragon's palette),
    # or pkgs.phinger-cursors / "phinger-cursors-light" (softer, rounder).
    cursor = {
      package = pkgs.runCommand "bibata-modern-ice" { } ''
        mkdir -p $out/share/icons
        cp -r ${pkgs.bibata-cursors}/share/icons/Bibata-Modern-Ice $out/share/icons/
      '';
      name = "Bibata-Modern-Ice";
      size = 24;
    };

    # Icon theme. Needed for app icons in the launcher (fuzzel reads
    # `icon-theme`, which Stylix only sets when this block is enabled — with it
    # off, icon lookup falls back to bare hicolor and renders almost nothing).
    #
    # Kanagawa rather than Adwaita for coverage: measured against the 39 distinct
    # icon names our installed .desktop files request, Adwaita resolves 2 and
    # Kanagawa 26 (the remainder come from apps shipping into hicolor). Adwaita
    # is a system-icon set — it has exactly one application icon. 64 MiB closure.
    # Not Papirus (~1 GiB, symlinks breeze-icons) or BeautyLine (~1.2 GiB).
    icons = {
      enable = true;
      package = pkgs.kanagawa-icon-theme;
      dark = "Kanagawa";
      light = "Kanagawa";
    };

    # Slight translucency on popups (launcher, notifications). Set here rather
    # than as a raw alpha in the fuzzel colors, because Stylix owns the whole
    # [colors] section and composes this into it.
    opacity.popups = 0.95;

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
