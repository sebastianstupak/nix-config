# Office suite. libreoffice-fresh is the GTK build — the stable path on
# wlroots/Hyprland (the Qt6 VCL backend has Wayland scroll/scaling issues).
{ pkgs, ... }:
{
  home.packages = with pkgs; [ libreoffice-fresh ];

  # If rendering ever looks blurry/laggy on Hyprland, force the GTK VCL plugin:
  # home.sessionVariables.SAL_USE_VCLPLUGIN = "gtk3";
}
